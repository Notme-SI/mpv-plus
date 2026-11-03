### Windows

- 🛠️ **Обновления:** исправлена остановка обновления TheIntroDB при изменении исходника. Доработки mpv+ перенесены на TheIntroDB 2.1.0; точные патчи отдельных участков сохраняют изменения вне их контекста и блокируют конфликтующие обновления.
- ⏭️ **Таймкоды:** используется API v4. При ограничении частоты запросов учитывается срок ожидания сервера; исчерпание дневного лимита прекращает повторные обращения до его окончания.
- 🧪 **Проверки:** добавлены проверки применения патчей, ответов API v4, лимитов и устаревших ответов после смены файла. Сохранены интеграции Lampa, AniSkip, дополнительные источники таймкодов и настройки пропусков.
- 📝 **Журнал:** убрана служебная строка прогресса PowerShell «Запись веб-запроса».

- 📦 **Компоненты:** mpv 2026-11-03-0d4aab5cf6 и FFmpeg ec887b13a. Контрольные суммы двоичных компонентов сверяются с манифестом сборки.

---

### 📚 Документация

- [Руководство: Lampa, TorrServer и настройки](https://github.com/Notme-SI/mpv-plus/blob/main/docs/USAGE.md)

- [История изменений](https://github.com/Notme-SI/mpv-plus/blob/main/CHANGELOG.md) · [Исходники и лицензии](https://github.com/Notme-SI/mpv-plus/blob/main/SOURCES.txt)

<p align="center">

  <img src="https://img.shields.io/badge/mpv%2B-v1.1.3-7c3aed?style=flat-square" alt="mpv+ v1.1.3">

</p>

### 📥 Скачать

| Система | Установщик | Портативная версия |
| --- | --- | --- |
| Windows 10/11 x64 | [![Setup x64](https://img.shields.io/badge/Windows-Setup_x64-0078D4?style=flat-square)](https://github.com/Notme-SI/mpv-plus/releases/download/v1.1.3/mpv%2B-1.1.3-Setup.exe) | [![Portable x64](https://img.shields.io/badge/Windows-Portable_x64-2496ED?style=flat-square)](https://github.com/Notme-SI/mpv-plus/releases/download/v1.1.3/mpv%2B-1.1.3.zip) |

Установщик — установка с выбором папки и созданием ярлыков. Портативная версия — распакуйте архив целиком.

Для Lampa Desktop выбирайте `mpv.exe` из папки mpv+. Самостоятельный запуск — `mpv+.exe`. При повторной установке в прежнюю папку личные настройки сохраняются.

Контрольные суммы SHA-256 доступны в блоке **Assets** под именами файлов и в [файле контрольных сумм](https://github.com/Notme-SI/mpv-plus/blob/main/releases/1.1.3/SHA256SUMS.txt). Архивы **Source code** содержат исходники, а не готовый плеер.
