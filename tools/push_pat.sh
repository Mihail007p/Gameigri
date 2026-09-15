#!/usr/bin/env bash
# Gameigri — резервный способ публикации: через Personal Access Token (когда Device Flow недоступен).
#
# Использование:
#   GITHUB_TOKEN=ghp_xxx bash tools/push_pat.sh            # запушить в существующий репозиторий
#   GITHUB_TOKEN=ghp_xxx bash tools/push_pat.sh RepoName   # создать репозиторий и запушить
#
# Токен берётся только из переменной окружения, никуда не пишется и не попадает в URL remote:
# используется одноразовый credential-helper, живущий лишь на время этой команды.
# Нужные права fine-grained токена: Contents: Read and write (+ Administration: Read and write
# для создания нового репозитория). Берите короткий срок и отзывайте сразу после пуша.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR" || exit 1

: "${GITHUB_TOKEN:?Не задан GITHUB_TOKEN. Запустите: GITHUB_TOKEN=xxx bash tools/push_pat.sh}"
NEW_NAME="${1:-}"

api() { curl -sS -H "Authorization: Bearer ${GITHUB_TOKEN}" \
               -H "Accept: application/vnd.github+json" \
               -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

echo "→ Проверяю токен..."
LOGIN=$(api https://api.github.com/user | python3 -c '
import sys, json
d = json.load(sys.stdin)
if "login" not in d: sys.exit("Ошибка авторизации: " + str(d.get("message")))
print(d["login"])')
echo "  пользователь: $LOGIN"

REPO_NAME="${NEW_NAME:-$(basename "$REPO_DIR")}"
if [ -n "$NEW_NAME" ]; then
  echo "→ Создаю репозиторий $LOGIN/$REPO_NAME (если есть — пропускаю)..."
  C=$(api -o /tmp/repo.json -w '%{http_code}' -X POST https://api.github.com/user/repos \
      -d "{\"name\":\"${REPO_NAME}\",\"private\":false}")
  [ "$C" = "201" ] && echo "  создан" ; [ "$C" = "422" ] && echo "  уже существует" ; \
  [ "$C" != "201" ] && [ "$C" != "422" ] && { echo "  ошибка $C:"; cat /tmp/repo.json; exit 1; }
fi

command -v node >/dev/null 2>&1 && [ -f tools/test_game.js ] && node tools/test_game.js >/tmp/t.log 2>&1 \
  && echo "→ Тесты: пройдены" || true

git add -A
git diff --cached --quiet || git -c user.name="$LOGIN" -c user.email="$LOGIN@users.noreply.github.com" \
  commit -q -m "chore: публикация"
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/${LOGIN}/${REPO_NAME}.git"

git -c credential.helper='!f() { echo username=x-access-token; echo "password=${GITHUB_TOKEN}"; }; f' \
    push -u origin main

echo
echo "✓ Опубликовано: https://github.com/${LOGIN}/${REPO_NAME}"
echo "  Не забудьте отозвать токен: GitHub → Settings → Developer settings → Tokens"
