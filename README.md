# Gameigri

Чистый стартовый репозиторий: минимальный HTML-файл + git.

## Структура

```
Gameigri/
├── index.html    # чистый HTML5-каркас
├── README.md
└── .gitignore
```

## Локальный запуск

Просто откройте `index.html` в браузере. Или поднимите локальный сервер:

```bash
python3 -m http.server 8000
# затем http://localhost:8000
```

## Публикация на GitHub

1. Создайте пустой репозиторий на GitHub (без README, без .gitignore) с именем `Gameigri`.
2. В этой папке выполните:

```bash
git remote add origin https://github.com/ВАШ_ЛОГИН/Gameigri.git
git branch -M main
git push -u origin main
```

Готово — код на GitHub.
