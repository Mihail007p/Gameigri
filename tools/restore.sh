#!/usr/bin/env bash
# Gameigri — восстановить проект в новой пустой среде (новый чат, новая песочница, новый компьютер).
#
# Использование:
#   bash restore.sh            # клонировать в ./Gameigri и прогнать тесты
#   bash restore.sh mydir      # клонировать в другую папку
#
# Смысл: рабочая область может исчезнуть в любой момент — весь код, журнал и память
# проекта живут в GitHub. Этот скрипт поднимает всё заново из репозитория.

set -uo pipefail
REPO="https://github.com/Mihail007p/Gameigri.git"
DIR="${1:-Gameigri}"

echo "=== 1/4 Проверка инструментов ==="
for t in git node curl; do
  command -v "$t" >/dev/null 2>&1 && echo "  ✓ $t: $(command -v $t)" || echo "  ✗ $t не найден — установите его"
done
CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://api.github.com || echo 000)
echo "  доступ к api.github.com: $CODE"

echo "=== 2/4 Клонирование $REPO → ./$DIR ==="
if [ -d "$DIR/.git" ]; then
  cd "$DIR" && git pull --ff-only && cd ..
  echo "  обновил существующую папку"
else
  git clone "$REPO" "$DIR" || { echo "  клонирование не удалось"; exit 1; }
fi
cd "$DIR" || exit 1

echo "=== 3/4 Что внутри ==="
git log --oneline -5
echo "  файлы:"; git ls-files | sed 's/^/    /'

echo "=== 4/4 Тесты ==="
if command -v node >/dev/null 2>&1; then
  node tools/test_game.js
else
  echo "  node недоступен — тесты пропущены. Игра всё равно откроется: $DIR/index.html"
fi

echo
echo "✓ Восстановлено: $PWD"
echo "  Дальше: откройте index.html, читайте PROGRESS.md, публикуйте через tools/gh_push.sh"
