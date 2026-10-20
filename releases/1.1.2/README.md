### Windows

- 🔎 **Распознавание аниме:** добавлен автоматический поиск в официальном каталоге MyAnimeList без ввода названий и MAL ID. В готовой сборке подключено приложение mpv+; аккаунт MAL пользователям не нужен.
- 🎯 **Точность:** проверяются альтернативные названия, известный год, тип выпуска и номер серии. Подтверждённые локальные ID сохраняют приоритет; неоднозначное совпадение не запускает пропуск.
- ⚡ **Загрузка данных:** запросы выполняются в фоне и кешируются; ответы после смены файла отбрасываются. При недоступности онлайн-каталога используется локальная база.
- ⏭️ **Пропуски:** убраны ручной поиск таймкодов и пункт AniSkip с вводом аниме. «Заставки и титры» открывает настройки напрямую; Ctrl+I сохранён. Изменения применяются и к старым персональным меню.
- 🛠️ **Обслуживание:** добавлена текущая версия плеера. Нажатие открывает её релиз на GitHub.

---

### 📚 Документация

- [Руководство: Lampa, TorrServer и настройки](https://github.com/Notme-SI/mpv-plus/blob/main/docs/USAGE.md)

- [История изменений](https://github.com/Notme-SI/mpv-plus/blob/main/CHANGELOG.md) · [Исходники и лицензии](https://github.com/Notme-SI/mpv-plus/blob/main/SOURCES.txt)

<p align="center">

  <img src="https://img.shields.io/badge/mpv%2B-v1.1.2-7c3aed?style=flat-square" alt="mpv+ v1.1.2">

</p>

### 📥 Скачать

| Система | Установщик | Портативная версия |
| --- | --- | --- |
| Windows 10/11 x64 | [![Setup x64](https://img.shields.io/badge/Windows-Setup_x64-0078D4?style=flat-square)](https://github.com/Notme-SI/mpv-plus/releases/download/v1.1.2/mpv%2B-1.1.2-Setup.exe) | [![Portable x64](https://img.shields.io/badge/Windows-Portable_x64-2496ED?style=flat-square)](https://github.com/Notme-SI/mpv-plus/releases/download/v1.1.2/mpv%2B-1.1.2.zip) |

Установщик — установка с выбором папки и созданием ярлыков. Портативная версия — распакуйте архив целиком.

Для Lampa Desktop выбирайте `mpv.exe` из папки mpv+. Самостоятельный запуск — `mpv+.exe`. При повторной установке в прежнюю папку личные настройки сохраняются.

Контрольные суммы SHA-256 доступны в блоке **Assets** под именами файлов и в [файле контрольных сумм](https://github.com/Notme-SI/mpv-plus/blob/main/releases/1.1.2/SHA256SUMS.txt). Архивы **Source code** содержат исходники, а не готовый плеер.
