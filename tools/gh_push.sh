#!/usr/bin/env bash
# Gameigri — публикация изменений на GitHub с авторизацией по одноразовому коду.
#
# Использование:
#   bash tools/gh_push.sh                        # коммит-сообщение по умолчанию
#   bash tools/gh_push.sh "feat: новая страница" # своё сообщение коммита
#
# Что делает:
#   1) поднимает gh CLI (скачивает, если его нет);
#   2) просит у GitHub одноразовый код, вы вводите его на https://github.com/login/device;
#   3) коммитит изменения и пушит ветку main;
#   4) удаляет файл с токеном.
# Пароль GitHub нигде не спрашивается и не сохраняется.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR" || exit 1

MSG="${1:-docs: обновление проекта}"
GH_VERSION="2.66.1"
GH_HOME="/tmp/gh-cli-$GH_VERSION"          # в /tmp — токен и бинарь не попадают в репозиторий
export XDG_CONFIG_HOME=/tmp/ghcfg XDG_CACHE_HOME=/tmp/ghcache
export GH_NO_UPDATE_NOTIFIER=1
mkdir -p "$XDG_CONFIG_HOME"

# --- 0. Проверка связи ------------------------------------------------------
CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://api.github.com || echo "000")
[ "$CODE" = "200" ] || { echo "Нет доступа к api.github.com (код $CODE). Проверьте интернет/прокси."; exit 1; }

# --- 1. gh CLI --------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  if [ ! -x "$GH_HOME/bin/gh" ]; then
    ARCH=$(uname -m); case "$ARCH" in x86_64) A=amd64;; aarch64|arm64) A=arm64;; *) A=amd64;; esac
    echo "→ Скачиваю gh CLI $GH_VERSION ($A)..."
    curl -sSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${A}.tar.gz" \
      -o /tmp/gh.tgz && mkdir -p "$GH_HOME" && tar xzf /tmp/gh.tgz -C /tmp && \
      rm -rf "$GH_HOME" && mv "/tmp/gh_${GH_VERSION}_linux_${A}" "$GH_HOME"
  fi
  export PATH="$GH_HOME/bin:$PATH"
fi
command -v gh >/dev/null 2>&1 || { echo "Не удалось получить gh CLI."; exit 1; }

# --- 2. Авторизация по одноразовому коду ------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "════════════════════════════════════════════════════════════"
  echo "  Авторизация: ниже появится одноразовый код (формат XXXX-XXXX)."
  echo "  1. Откройте https://github.com/login/device"
  echo "  2. Введите код, нажмите Authorize."
  echo "════════════════════════════════════════════════════════════"
  printf '\n\n\n\n' | gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key
  gh auth status >/dev/null 2>&1 || { echo "Авторизация не завершена (код истёк?). Запустите скрипт ещё раз."; exit 1; }
fi
LOGIN=$(gh api user --jq .login)
echo "→ Авторизован как: $LOGIN"

# --- 3. Коммит и push -------------------------------------------------------
git add -A
if ! git diff --cached --quiet; then
  git -c user.name="$LOGIN" -c user.email="${LOGIN}@users.noreply.github.com" commit -q -m "$MSG"
  echo "→ Коммит: $(git log -1 --oneline)"
else
  echo "→ Изменений для коммита нет"
fi
git branch -M main
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$LOGIN/$(basename "$REPO_DIR").git"
gh auth setup-git >/dev/null 2>&1
git push -u origin main

# --- 4. Уборка токена -------------------------------------------------------
rm -f "$XDG_CONFIG_HOME/gh/hosts.yml"

echo
echo "✓ Готово: https://github.com/${LOGIN}/Gameigri"
echo "  Токен удалён. Отозвать доступ: Settings → Applications → GitHub CLI → Revoke"
