#!/usr/bin/env bash
# Gameigri — публикация на GitHub через Device Flow «вручную»: устойчиво к сетевым сбоям и rate-limit.
#
# Зачем, если есть tools/gh_push.sh: gh CLI падает при первом же обрыве соединения
# (read: connection reset by peer) и теряет выданный код. Здесь — повторы, обход slow_down,
# и токен сразу используется для push, а затем уничтожается.
#
# Использование:
#   bash tools/device_push.sh "сообщение коммита" [--pages]
#
# Авторизация: скрипт выдаст код вида XXXX-XXXX, его нужно ввести на https://github.com/login/device
# (страница «Authorize GitHub CLI»). Пароль не требуется, доступ можно отозвать в любой момент.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR" || exit 1

MSG="chore: обновление проекта"; PAGES=0
for a in "$@"; do
  case "$a" in --pages) PAGES=1 ;; *) MSG="$a" ;; esac
done

CLIENT_ID="178c6fc778ccc68e1d6a"     # официальное OAuth-приложение GitHub CLI (публичный client_id)
SCOPE="repo workflow"
TOKEN_FILE="/tmp/gh_device_token"    # вне рабочей области; удаляется в конце
: > "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"

J() { python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$1',''))" 2>/dev/null; }
# POST с повторами: сеть в песочнице бывает рваной
post() {
  curl -sS --retry 6 --retry-all-errors --retry-delay 2 --max-time 30 \
       -H "Accept: application/json" -X POST "$1" -d "$2" 2>/dev/null
}

echo "=== [1/5] Запрашиваю одноразовый код ==="
DEV=""; tries=0
while [ -z "$DEV" ] && [ "$tries" -lt 5 ]; do
  tries=$((tries+1))
  RESP=$(post https://github.com/login/device/code "client_id=${CLIENT_ID}&scope=${SCOPE}")
  DEV=$(printf '%s' "$RESP" | J device_code)
  [ -z "$DEV" ] && { echo "  попытка $tries не удалась, повтор..."; sleep 3; }
done
[ -n "$DEV" ] || { echo "Не удалось получить код. Проверьте интернет."; exit 1; }

USER_CODE=$(printf '%s' "$RESP" | J user_code)
VERIFY=$(printf '%s' "$RESP" | J verification_uri); VERIFY="${VERIFY:-https://github.com/login/device}"
INTERVAL=$(printf '%s' "$RESP" | J interval); INTERVAL="${INTERVAL:-5}"
EXPIRES=$(printf '%s' "$RESP" | J expires_in); EXPIRES="${EXPIRES:-900}"

echo
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ОДНОРАЗОВЫЙ КОД:  ${USER_CODE}                          "
echo "║   1. Откройте: ${VERIFY}    "
echo "║   2. Введите код и нажмите Authorize                      "
echo "║   Код действует ${EXPIRES} секунд. Скрипт ждёт и сам продолжит.  "
echo "╚══════════════════════════════════════════════════════════╝"
echo

echo "=== [2/5] Жду подтверждения (обрывы сети не страшны, будут повторы) ==="
DEADLINE=$(( $(date +%s) + EXPIRES ))
TOKEN=""; netfail=0
while [ -z "$TOKEN" ] && [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep "$INTERVAL"
  RESP=$(post https://github.com/login/oauth/access_token \
      "client_id=${CLIENT_ID}&device_code=${DEV}&grant_type=urn:ietf:params:oauth:grant-type:device_code")
  if [ -z "$RESP" ]; then
    netfail=$((netfail+1)); printf '.'; continue
  fi
  TOKEN=$(printf '%s' "$RESP" | J access_token)
  [ -n "$TOKEN" ] && break
  ERR=$(printf '%s' "$RESP" | J error)
  case "$ERR" in
    authorization_pending) printf '.' ;;
    slow_down)             INTERVAL=$((INTERVAL+5)); printf '+' ;;
    expired_token)         echo; echo "Код истёк — запустите скрипт заново."; exit 1 ;;
    access_denied)         echo; echo "Доступ отклонён владельцем."; exit 1 ;;
    *)                     printf '?' ;;
  esac
done
echo
[ -n "$TOKEN" ] || { echo "Не дождались подтверждения (сетевых сбоев: ${netfail}). Запустите скрипт ещё раз."; exit 1; }
echo "✓ Доступ выдан"
printf '%s' "$TOKEN" > "$TOKEN_FILE"

api() { curl -sS --retry 5 --retry-all-errors -H "Authorization: Bearer ${TOKEN}" \
              -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

LOGIN=$(api https://api.github.com/user | J login)
REPO_NAME=$(basename "$REPO_DIR")
echo "=== [3/5] Пользователь: ${LOGIN:-не определён} · репозиторий: $REPO_NAME ==="
[ -n "$LOGIN" ] || { echo "Токен не работает."; rm -f "$TOKEN_FILE"; exit 1; }

# Ранняя проверка: есть ли у токена доступ к репозиторию и право на запись.
# Лучше узнать это сейчас, чем получить «Invalid username or token» на самом пуше.
REPO_JSON=$(api "https://api.github.com/repos/${LOGIN}/${REPO_NAME}")
echo "$REPO_JSON" | J full_name | grep -q . \
  || { echo "  !!! токен не видит репозиторий ${LOGIN}/${REPO_NAME}"; echo "$REPO_JSON" | head -3; rm -f "$TOKEN_FILE"; exit 1; }
PUSH_OK=$(echo "$REPO_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin).get('permissions',{}).get('push',False))" 2>/dev/null)
echo "  права на push: ${PUSH_OK}"

# тесты перед публикацией
if command -v node >/dev/null 2>&1 && [ -f tools/test_game.js ]; then
  if node tools/test_game.js >/tmp/test_game.log 2>&1; then
    echo "  тесты: пройдены ($(grep -c '✓' /tmp/test_game.log) проверок)"
  else
    echo "  !!! тесты не пройдены — пуш отменён"; tail -15 /tmp/test_game.log; rm -f "$TOKEN_FILE"; exit 1
  fi
fi

git add -A
if ! git diff --cached --quiet; then
  git -c user.name="$LOGIN" -c user.email="${LOGIN}@users.noreply.github.com" commit -q -m "$MSG"
  echo "  коммит: $(git log -1 --oneline)"
else
  echo "  новых изменений нет (публикую то, что есть)"
fi
git branch -M main
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/${LOGIN}/${REPO_NAME}.git"

echo "=== [4/5] Push ветки main ==="
# ВАЖНО: переменная с токеном обязана быть экспортирована — иначе git запустит credential-helper
# в дочернем процессе, где переменная пуста, и получит «Invalid username or token».
export GH_TOKEN="$TOKEN"
cat > /tmp/gh_askpass.sh <<'ASKPASS'
#!/bin/sh
# git спрашивает логин и пароль двумя вызовами: отвечаем токеном через переменную окружения
case "$1" in
  *sername*) echo "x-access-token" ;;
  *)         echo "$GH_TOKEN" ;;
esac
ASKPASS
chmod +x /tmp/gh_askpass.sh

push_with_token() {
  # -c credential.helper= обнуляет список хелперов, чтобы не мешали сторонние настройки
  git -c credential.helper= -c core.askpass=/tmp/gh_askpass.sh push -u origin main 2>&1
}
if ! push_with_token; then
  echo "  первая попытка не удалась, повторяю..."
  sleep 3
  push_with_token || { echo "push не удался"; rm -f "$TOKEN_FILE" /tmp/gh_askpass.sh; exit 1; }
fi

if [ "$PAGES" = "1" ]; then
  echo "=== Pages ==="
  api -X POST "https://api.github.com/repos/${LOGIN}/${REPO_NAME}/pages" \
      -d '{"source":{"branch":"main","path":"/"}}' >/dev/null
  SITE=$(api "https://api.github.com/repos/${LOGIN}/${REPO_NAME}/pages" | J html_url)
  echo "  сайт: ${SITE:-включается, ссылка появится через минуту}"
fi

echo "=== [5/5] Уборка токена ==="
rm -f "$TOKEN_FILE" /tmp/gh_askpass.sh && echo "  файл с токеном и askpass-скрипт удалены"
TOKEN=""

echo
echo "✓ Опубликовано: https://github.com/${LOGIN}/${REPO_NAME}"
echo "  Коммитов в main: $(git rev-list --count main)"
echo "  Отозвать доступ: GitHub → Settings → Applications → GitHub CLI → Revoke"
