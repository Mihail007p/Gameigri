#!/usr/bin/env bash
# Gameigri — создать НОВЫЙ репозиторий на GitHub из папки и запушить (Device Flow, без пароля).
#
# Использование (из папки проекта):
#   bash tools/deploy_new.sh RepoName "описание"        # публичный
#   bash tools/deploy_new.sh RepoName "описание" --private
#
# Отличие от tools/gh_push.sh: тот пушит в УЖЕ существующий репозиторий,
# этот — создаёт новый через API.

set -uo pipefail
NAME="${1:?Укажите имя репозитория: bash tools/deploy_new.sh RepoName \"описание\"}"
DESC="${2:-проект}"
VIS="public"; [ "${3:-}" = "--private" ] && VIS="private"

export XDG_CONFIG_HOME=/tmp/ghcfg XDG_CACHE_HOME=/tmp/ghcache GH_NO_UPDATE_NOTIFIER=1
mkdir -p "$XDG_CONFIG_HOME"
GVER=2.66.1; GHOME="/tmp/gh-cli-$GVER"
if ! command -v gh >/dev/null 2>&1; then
  [ -x "$GHOME/bin/gh" ] || {
    echo "→ Скачиваю gh CLI..."; mkdir -p "$GHOME"
    curl -sSL "https://github.com/cli/cli/releases/download/v$GVER/gh_${GVER}_linux_amd64.tar.gz" -o /tmp/gh.tgz
    tar xzf /tmp/gh.tgz -C /tmp && rm -rf "$GHOME" && mv "/tmp/gh_${GVER}_linux_amd64" "$GHOME"
  }
  export PATH="$GHOME/bin:$PATH"
fi

echo "### Авторизация (введите код на https://github.com/login/device)"
printf '\n\n\n\n\n\n\n\n\n\n' | gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key
gh auth status >/dev/null 2>&1 || { echo "!!! Авторизация не завершена."; exit 1; }
LOGIN=$(gh api user --jq .login)

[ -d .git ] || { echo "Инициализирую git..."; git init -q; }
git add -A
git diff --cached --quiet || git -c user.name="$LOGIN" -c user.email="$LOGIN@users.noreply.github.com" \
  commit -q -m "chore: первичная публикация $NAME"
git branch -M main

echo "### Создаю репозиторий $LOGIN/$NAME ($VIS)"
gh repo create "$NAME" "--$VIS" --source=. --remote=origin --push --description "$DESC"
rm -f "$XDG_CONFIG_HOME/gh/hosts.yml"

echo
echo "✓ Готово: https://github.com/$LOGIN/$NAME"
echo "  Токен удалён. Отозвать доступ: Settings → Applications → GitHub CLI → Revoke"
