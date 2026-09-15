#!/usr/bin/env bash
# Gameigri — закоммитить и запушить изменения на GitHub. Авторизация — одноразовый код (без пароля).
#
# Использование:
#   bash tools/gh_push.sh                          # коммит с сообщением по умолчанию
#   bash tools/gh_push.sh "feat: новая фича"       # своё сообщение коммита
#   bash tools/gh_push.sh --pages                  # ещё и включить GitHub Pages
#   bash tools/gh_push.sh "fix: баг" --pages       # комбинация
#
# Что делает: поднимает gh CLI (скачает при необходимости) → Device Flow → commit → push →
# (опционально) включает Pages → удаляет файл с токеном. Пароль GitHub нигде не спрашивается.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR" || exit 1

MSG="docs: обновление проекта"; PAGES=0
for a in "$@"; do
  case "$a" in
    --pages) PAGES=1 ;;
    *) MSG="$a" ;;
  esac
done

export XDG_CONFIG_HOME=/tmp/ghcfg XDG_CACHE_HOME=/tmp/ghcache GH_NO_UPDATE_NOTIFIER=1
mkdir -p "$XDG_CONFIG_HOME"
GVER=2.66.1; GHOME="/tmp/gh-cli-$GVER"

# --- 0. Связь --------------------------------------------------------------
CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://api.github.com || echo 000)
[ "$CODE" = "200" ] || { echo "Нет доступа к api.github.com (код $CODE). Проверьте интернет/прокси."; exit 1; }

# --- 1. gh CLI -------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  [ -x "$GHOME/bin/gh" ] || {
    ARCH=$(uname -m); case "$ARCH" in aarch64|arm64) A=arm64;; *) A=amd64;; esac
    echo "→ Скачиваю gh CLI $GVER ($A)..."; mkdir -p "$GHOME"
    curl -sSL "https://github.com/cli/cli/releases/download/v${GVER}/gh_${GVER}_linux_${A}.tar.gz" -o /tmp/gh.tgz
    tar xzf /tmp/gh.tgz -C /tmp && rm -rf "$GHOME" && mv "/tmp/gh_${GVER}_linux_${A}" "$GHOME"
  }
  export PATH="$GHOME/bin:$PATH"
fi
command -v gh >/dev/null 2>&1 || { echo "Не удалось получить gh CLI."; exit 1; }

# --- 2. Авторизация по одноразовому коду ------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "════════════════════════════════════════════════════════════"
  echo "  Авторизация: ниже появится одноразовый код (XXXX-XXXX)."
  echo "  1. Откройте https://github.com/login/device"
  echo "  2. Введите код и нажмите Authorize."
  echo "════════════════════════════════════════════════════════════"
  printf '\n\n\n\n' | gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key
  gh auth status >/dev/null 2>&1 || { echo "Авторизация не завершена (код истёк?). Запустите скрипт ещё раз."; exit 1; }
fi
LOGIN=$(gh api user --jq .login)
REPO_NAME=$(gh repo view --json name --jq .name 2>/dev/null || basename "$REPO_DIR")
echo "→ Авторизован как: $LOGIN · репозиторий: $REPO_NAME"

# --- 3. Тесты перед публикацией --------------------------------------------
if command -v node >/dev/null 2>&1 && [ -f tools/test_game.js ]; then
  if ! node tools/test_game.js >/tmp/test_game.log 2>&1; then
    echo "!!! Тесты не пройдены — пуш отменён. Подробности: /tmp/test_game.log"
    tail -20 /tmp/test_game.log
    exit 1
  fi
  echo "→ Тесты: пройдены ($(grep -c '✓' /tmp/test_game.log) проверок)"
fi

# --- 4. Коммит и push -------------------------------------------------------
git add -A
if ! git diff --cached --quiet; then
  git -c user.name="$LOGIN" -c user.email="${LOGIN}@users.noreply.github.com" commit -q -m "$MSG"
  echo "→ Коммит: $(git log -1 --oneline)"
else
  echo "→ Новых изменений нет"
fi
git branch -M main
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$LOGIN/$REPO_NAME.git"
gh auth setup-git >/dev/null 2>&1
git push -u origin main

# --- 5. GitHub Pages (опционально) ------------------------------------------
if [ "$PAGES" = "1" ]; then
  echo "→ Включаю GitHub Pages..."
  gh api --method POST "repos/$LOGIN/$REPO_NAME/pages" \
     -f 'source[branch]=main' -f 'source[path]=/' >/dev/null 2>&1 || true
  URL=$(gh api "repos/$LOGIN/$REPO_NAME/pages" --jq .html_url 2>/dev/null)
  echo "  сайт: ${URL:-включается, ссылка появится через ~1 минуту}"
fi

# --- 6. Уборка токена -------------------------------------------------------
rm -f "$XDG_CONFIG_HOME/gh/hosts.yml"

echo
echo "✓ Опубликовано: https://github.com/$LOGIN/$REPO_NAME"
echo "  Коммитов в main: $(git rev-list --count main). Токен удалён."
echo "  Отозвать доступ: GitHub → Settings → Applications → GitHub CLI → Revoke"
