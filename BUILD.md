# Сборка ZIP и установщика

Команды выполняются в PowerShell из корня репозитория на Windows x64. Нужны Git, Python 3, .NET Framework 4 с компилятором `csc.exe` в `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319` и, для установщика, [Inno Setup 6.7.3](https://jrsoftware.org/isdl.php).

Номер собираемой версии хранится в [`VERSION`](VERSION). Команды ниже читают его из файла; имена результатов не нужно менять в инструкции при каждом выпуске.

## Подготовка данных

Создайте компактный каталог из снимков [anime-offline-database](https://github.com/manami-project/anime-offline-database) (`anime-offline-database.json`) и [Fribb/anime-lists](https://github.com/Fribb/anime-lists) (`anime-list-full.json`):

```powershell
python tools/build-anime-catalog.py --database "C:\Downloads\anime-offline-database.json" --mapping "C:\Downloads\anime-list-full.json"
```

Результат — `portable_config/data/anime-catalog.json`. Он исключён из Git. Без пересборки каталога используется снимок из проверенной базы 1.0.3. Источники и лицензии данных перечислены в [`SOURCES.txt`](SOURCES.txt). Для воспроизведения конкретного каталога используйте те же снимки входных JSON.

## ZIP

Скачайте чистый [`mpv+-1.0.3.zip`](https://github.com/Notme-SI/mpv-plus/releases/tag/v1.0.3). Это фиксированная база с двоичными компонентами, шрифтами и данными. Скрипт сверяет SHA-256 по [`releases/1.0.3/SHA256SUMS.txt`](releases/1.0.3/SHA256SUMS.txt). Подставлять вместо него произвольный последний выпуск нельзя. В сборку входят только отслеживаемые Git исходники: сначала добавьте новые файлы через `git add`.

```powershell
$releaseVersion = (Get-Content -LiteralPath .\VERSION -Raw).Trim()
python tools/build-package.py --base "C:\Downloads\mpv+-1.0.3.zip"
```

Результаты: `dist/mpv+-<версия>.zip` и `dist/mpv+-<версия>.zip.sha256`. Исходный ZIP не изменяется. Скрипт накладывает файлы текущего checkout, переименовывает основной плеер в `mpv+.exe` и компилирует совместимый запускатель `mpv.exe` для Lampa.

Основной набор берётся из `git ls-files`; новые файлы сначала добавляйте в Git. Каталоги `portable_config/extensions`, `portable_config/scripts` и `portable_config/maintenance` дополнительно включаются целиком, кроме `__pycache__`. Собирайте из чистого checkout без личных и временных файлов в этих каталогах.

Команда использует двоичные компоненты фиксированного базового архива. Она не запускает обновление компонентов и не гарантирует совпадения всего ZIP с опубликованным выпуском. Состав конкретного выпуска проверяйте по его манифесту и контрольным суммам.

## Установщик

```powershell
$releaseVersion = (Get-Content -LiteralPath .\VERSION -Raw).Trim()
python installer/prepare.py "dist/mpv+-$releaseVersion.zip"
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer/MPV.iss
```

Результат — `installer/output/mpv+-<версия>-Setup.exe`. Путь к ISCC зависит от места установки Inno Setup. Значение `AppVersion` в `installer/MPV.iss` должно совпадать с `VERSION`.

Подготовка сверяет ZIP с соседним файлом `.sha256`, создаёт `installer/payload`, `installer/files.iss` и `installer/payload-manifest.json`. При повторной сборке используйте чистый checkout либо заранее уберите старый `installer/payload`: скрипт подготовки не удаляет оставшиеся от предыдущего архива файлы.

Установка выполняется для текущего пользователя. При переустановке сохраняются `mpv.conf`, `input.conf`, все файлы `script-opts` и личное состояние плеера. При удалении личные настройки остаются на месте.

## Проверка

Распакуйте результат в отдельную доступную для записи папку. Перейдите в папку рядом с `mpv+.exe` и выполните:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\portable_config\maintenance\Test-Extensions.ps1 -Executable .\mpv+.exe -ConfigRoot .\portable_config
```

Успех подтверждается сообщением «Проверено: …» и кодом выхода `0`. На одних исходниках без двоичных компонентов эта проверка не запускается.

Установщик проверяйте отдельно: установка, запуск обоих исполняемых файлов, изменение настроек, повторная установка и удаление. Дополнительно проверьте язык интерфейса, подключение к тестовому TorrServer и создание личной резервной копии. Не используйте рабочую установку плеера для проверки выпуска.

## Публикация

1. Обновите `VERSION` и `AppVersion` в `installer/MPV.iss`. `AppId` установщика сохраняйте прежним.
2. Добавьте запись в `CHANGELOG.md`, описание в `releases/<версия>/README.md` и актуальные сведения об изменённых компонентах в `SOURCES.txt` и манифесте.
3. Соберите и проверьте ZIP и установщик. После всех изменений файлов вычислите SHA-256:

   ```powershell
   $releaseVersion = (Get-Content -LiteralPath .\VERSION -Raw).Trim()
   Get-FileHash -Algorithm SHA256 -LiteralPath "dist/mpv+-$releaseVersion.zip", "installer/output/mpv+-$releaseVersion-Setup.exe"
   ```

4. Запишите суммы в `releases/<версия>/SHA256SUMS.txt` в формате `<sha256>  <имя файла>`. Разместите проверенные ZIP и установщик в GitHub Releases с тегом `v<версия>`.
5. Проверьте, что ссылка [на последний выпуск](https://github.com/Notme-SI/mpv-plus/releases/latest) открывает нужный релиз. Workflow автоматически обновит кнопки скачивания в README по данным этого выпуска. Оформление описаний и повторный запуск workflow описаны в [инструкции по релизам](docs/RELEASES.md). Общие инструкции и `README.txt` не требуют подстановки нового номера.

Не копируйте в репозиторий личную установку: она может содержать пароль TorrServer, токены, историю и кэш. В `script-opts` хранятся только чистые настройки по умолчанию. [Исторический отчёт 1.0.1](releases/1.0.1/PUBLIC-AUDIT.txt) относится только к этому выпуску; он не заменяет проверку нового архива.
