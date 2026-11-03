param(
    [ValidateSet('Interactive','Check','Update','Verify')][string]$Mode='Interactive',
    [switch]$Library,
    [string]$ReportPath,
    [string]$ProgressPath
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if($PSVersionTable.PSVersion.Major -eq 5) { $env:PSModulePath=[Environment]::GetEnvironmentVariable('PSModulePath','Machine') }
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$Utf8=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=$Utf8
$OutputEncoding=$Utf8
function Normalize([string]$Text) { return $Text.Replace("`r`n","`n").TrimEnd("`r","`n")+"`n" }
function Write-Utf8([string]$Path,[string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text,$Utf8)
}
function Report-Progress([string]$Stage,[string]$Component='') {
    if($ProgressPath) { Write-Utf8 $ProgressPath (@{stage=$Stage;component=$Component}|ConvertTo-Json -Compress) }
}
function Apply-Patches([string]$Text,$Patches) {
    $Text=Normalize $Text
    foreach($patch in $Patches) {
        $start=$Text.IndexOf([string]$patch.before,[StringComparison]::Ordinal)
        if($start -lt 0 -or $Text.IndexOf([string]$patch.before,$start+1,[StringComparison]::Ordinal) -ge 0) {
            throw 'Исходник изменился рядом с нашей доработкой. Этот мод оставлен без изменений.'
        }
        $Text=$Text.Substring(0,$start)+[string]$patch.after+$Text.Substring($start+([string]$patch.before).Length)
    }
    return $Text
}
function Get-Api([string]$Url) {
    return Invoke-RestMethod -Uri $Url -Headers @{Accept='application/vnd.github+json'} -UserAgent 'mpv-personal-build-updater' -TimeoutSec 30
}
function Download-Asset($Asset,[string]$Path) {
    if(!$Asset.digest -or $Asset.digest -notmatch '^sha256:([a-f0-9]{64})$') { throw 'В релизе нет контрольной суммы SHA-256.' }
    $expected=$Matches[1]
    Invoke-WebRequest -UseBasicParsing -Uri $Asset.browser_download_url -OutFile $Path -UserAgent 'mpv-personal-build-updater' -TimeoutSec 180
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $expected) { throw 'Контрольная сумма загрузки не совпала.' }
}
function Copy-Folder([string]$Source,[string]$Destination) {
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach($item in Get-ChildItem -LiteralPath $Source -Force) { Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force }
}
function Test-PlayerProcess([string]$ProcessPath,[string]$Executable) {
    if(!$ProcessPath -or !$Executable) { return $false }
    return [string]::Equals([IO.Path]::GetFullPath($ProcessPath),[IO.Path]::GetFullPath($Executable),[StringComparison]::OrdinalIgnoreCase)
}
function Assert-PlayerClosed([string]$Executable) {
    # Other installations and the small mpv.exe forwarding launcher do not lock
    # this executable. The staged smoke-test player is a different path as well.
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do {
        $running=@(Get-Process -Name 'mpv','mpv+' -ErrorAction SilentlyContinue | Where-Object {
            Test-PlayerProcess $_.Path $Executable
        })
        if(!$running.Count) { return }
        Start-Sleep -Milliseconds 250
    } while([DateTime]::UtcNow -lt $deadline)
    throw ('Закройте обновляемую копию плеера: '+$Executable)
}
if($Library) { return }
$ConfigRoot=Split-Path -Parent $PSScriptRoot
$manifestPath=Join-Path $PSScriptRoot 'manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$portableRoot=Split-Path -Parent $ConfigRoot
$PlayerRoot=if((Test-Path -LiteralPath (Join-Path $portableRoot 'mpv+.exe')) -or (Test-Path -LiteralPath (Join-Path $portableRoot 'mpv.exe'))) { $portableRoot } else { [string]$manifest.playerRoot }
$exe=Join-Path $PlayerRoot 'mpv+.exe'
if(!(Test-Path -LiteralPath $exe)) {
    if(Test-Path -LiteralPath (Join-Path $portableRoot 'mpv.exe')) {$PlayerRoot=$portableRoot;$exe=Join-Path $PlayerRoot 'mpv.exe'}
    else {throw 'Не найден плеер. Переносите всю папку сборки.'}
}
$cache=@{}
$available=New-Object Collections.ArrayList
$reports=New-Object Collections.ArrayList
$checkErrors=0
$locallyModified=0
foreach($entry in $manifest.entries) {
    Report-Progress 'checking' $entry.name
    try {
        $meta=$null; $asset=$null; $releaseTag=$null
        $scope=if($entry.scope -eq 'player') {$PlayerRoot} else {$ConfigRoot}
        $target=Join-Path $scope $entry.path
        if($entry.kind -eq 'source') {
            $meta=Get-Api ('https://api.github.com/repos/'+$entry.repo+'/contents/'+$entry.remotePath)
            $remoteVersion=[string]$meta.sha
        } else {
            if(!$cache.ContainsKey($entry.repo)) { $cache[$entry.repo]=Get-Api ('https://api.github.com/repos/'+$entry.repo+'/releases/latest') }
            $release=$cache[$entry.repo]
            $releaseTag=[string]$release.tag_name
            $asset=@($release.assets | Where-Object {$_.name -match $entry.assetPattern})
            if($asset.Count -ne 1) { throw 'Не удалось однозначно выбрать файл релиза.' }
            $asset=$asset[0]
            $remoteVersion=if($entry.kind -eq 'ffmpeg') {[string]$asset.name} else {[string]$release.tag_name}
        }
        $modified=(!(Test-Path -LiteralPath $target)) -or ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.installedHash)
        if($entry.kind -eq 'uosc' -and $entry.installedFiles) {
            foreach($file in $entry.installedFiles.PSObject.Properties) {
                $path=Join-Path $scope $file.Name
                if(!(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.Value) { $modified=$true; break }
            }
        }
        $changed=$remoteVersion -ne $entry.version
        $status=if($modified) {'Локально изменён - сохранён'} elseif($changed) {'Есть обновление'} else {'Актуально'}
        [void]$reports.Add([pscustomobject]@{Компонент=$entry.name; Состояние=$status})
        if($modified) { $locallyModified++; continue }
        $eligible=if($Mode -eq 'Verify') {$entry.kind -in @('source','uosc')} else {$changed}
        if($eligible) {
            [void]$available.Add([pscustomobject]@{entry=$entry; version=$remoteVersion; meta=$meta; asset=$asset; releaseTag=$releaseTag})
        }
    } catch {
        $checkErrors++
        [void]$reports.Add([pscustomobject]@{Компонент=$entry.name; Состояние=('Не удалось проверить: '+$_.Exception.Message)})
    }
}
if($ReportPath) {
    $rows=@($reports | ForEach-Object { @{name=$_.Компонент;status=$_.Состояние} })
    Write-Utf8 $ReportPath (@{components=$rows;available=$available.Count;failed=($checkErrors -gt 0)}|ConvertTo-Json -Depth 5)
}
$reports | Format-Table -AutoSize -Wrap | Out-Host
if($available.Count -eq 0) {
    Report-Progress 'complete'
    if($checkErrors -gt 0) { Write-Host 'Проверка завершена не полностью. Повторите позже.'; exit 1 }
    if($locallyModified -gt 0) { Write-Host 'Доступных обновлений нет. Локально изменённые компоненты пропущены.'; exit 0 }
    Write-Host 'Проверка завершена. Обновление не требуется.'
    exit 0
}
if($Mode -eq 'Check') { Write-Host 'Проверка завершена. Есть доступные обновления.'; exit 0 }
if($checkErrors -gt 0) { Write-Host 'Часть компонентов не удалось проверить. Будут обновлены только проверенные.' }
if($Mode -eq 'Interactive') {
    do {
        $answer=([string](Read-Host 'Обновить? (Y/N)')).Trim()
        if($answer -notmatch '^[yn]$') { Write-Host 'Введите Y или N и нажмите Enter.' }
    } while($answer -notmatch '^[yn]$')
    if($answer -ieq 'N') { Write-Host 'Обновление отменено.'; exit 0 }
}
if($Mode -ne 'Verify') {
    Assert-PlayerClosed $exe
    $writeRoots=@($ConfigRoot)
    if(@($available | Where-Object {$_.entry.scope -eq 'player'}).Count -gt 0) { $writeRoots+=@($PlayerRoot) }
    foreach($root in $writeRoots) {
        try {
            $probe=Join-Path $root ('.write-'+[guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($probe,'')
            Remove-Item -LiteralPath $probe
        } catch { throw 'Нет доступа для установки. Повторите обновление из меню и подтвердите запрос Windows.' }
    }
}
$work=Join-Path $env:TEMP ('mpv-update-'+[guid]::NewGuid().ToString('N'))
$preparedConfig=Join-Path $work 'config'
$preparedPlayer=Join-Path $work 'player'
Copy-Folder $ConfigRoot $preparedConfig
[IO.Directory]::CreateDirectory($preparedPlayer)|Out-Null
$candidates=New-Object Collections.ArrayList
$prepareErrors=0
foreach($update in $available) {
    $entry=$update.entry; $remoteVersion=$update.version; $meta=$update.meta; $asset=$update.asset
    Report-Progress 'preparing' $entry.name
    try {
        # Stage each component in isolation; a rejected download must never leak
        # partially copied files into another component's validation.
        $destinationRoot=Join-Path $work ('component-'+$entry.name)
        [IO.Directory]::CreateDirectory($destinationRoot)|Out-Null
        $files=New-Object Collections.ArrayList
        if($entry.kind -eq 'source') {
            $raw=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($meta.content -replace '\s','')))
            $patched=$raw
            if($entry.patchFile) {
                $patches=Get-Content -LiteralPath (Join-Path $PSScriptRoot $entry.patchFile) -Raw -Encoding UTF8 | ConvertFrom-Json
                $patched=Apply-Patches $raw $patches
            }
            Write-Utf8 (Join-Path $destinationRoot $entry.path) $patched
            [void]$files.Add([string]$entry.path)
        } elseif($entry.kind -eq 'guessit') {
            [IO.Directory]::CreateDirectory((Split-Path -Parent (Join-Path $destinationRoot $entry.path)))|Out-Null
            Download-Asset $asset (Join-Path $destinationRoot $entry.path)
            [void]$files.Add([string]$entry.path)
        } else {
            $download=Join-Path $work $asset.name
            Download-Asset $asset $download
            $unpack=Join-Path $work ('extract-'+$entry.name)
            [IO.Directory]::CreateDirectory($unpack)|Out-Null
            if($entry.kind -eq 'uosc') { Expand-Archive -LiteralPath $download -DestinationPath $unpack }
            else {
                $seven=Join-Path $PlayerRoot '7z\7zr.exe'
                if(!(Test-Path -LiteralPath $seven)) { throw 'Не найден 7z/7zr.exe из сборки mpv.' }
                & $seven x -y "-o$unpack" $download | Out-Null
                if($LASTEXITCODE -ne 0) { throw 'Не удалось распаковать релиз.' }
            }
            if($entry.kind -eq 'uosc') {
                foreach($dir in @('scripts\uosc','fonts')) {
                    $base=Join-Path $unpack $dir
                    if(!(Test-Path -LiteralPath $base)) { throw 'Неожиданная структура архива uosc.' }
                    foreach($f in Get-ChildItem -LiteralPath $base -Recurse -File) {
                        $rel=$f.FullName.Substring($unpack.Length+1)
                        if($rel -eq 'scripts\uosc\main.lua') { $rel='vendor\uosc\main.lua' }
                        $dest=Join-Path $destinationRoot $rel
                        [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
                        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
                        [void]$files.Add($rel)
                    }
                }
            } else {
                $names=if($entry.kind -eq 'mpv') {@('mpv.exe')} else {@('ffmpeg.exe')}
                foreach($name in $names) {
                    $found=@(Get-ChildItem -LiteralPath $unpack -Recurse -File -Filter $name)
                    if($found.Count -ne 1) { throw "В архиве не найден $name" }
                    $destName=if($entry.kind -eq 'mpv') {'mpv+.exe'} else {$name}
                    Copy-Item -LiteralPath $found[0].FullName -Destination (Join-Path $destinationRoot $destName) -Force
                    [void]$files.Add($destName)
                }
            }
        }
        if($entry.kind -eq 'mpv') {
            $entry.upstreamHash=(Get-FileHash -LiteralPath (Join-Path $destinationRoot 'mpv+.exe') -Algorithm SHA256).Hash
            & (Join-Path $PSScriptRoot 'Set-MPVIcon.ps1') -ExecutablePath (Join-Path $destinationRoot 'mpv+.exe') -IconPath (Join-Path $ConfigRoot 'assets/mpv-monochrome.ico')
        }
        $mergeRoot=if($entry.scope -eq 'player') {$preparedPlayer} else {$preparedConfig}
        foreach($rel in $files) {
            $dest=Join-Path $mergeRoot $rel
            [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
            Copy-Item -LiteralPath (Join-Path $destinationRoot $rel) -Destination $dest -Force
        }
        [void]$candidates.Add([pscustomobject]@{entry=$entry; version=$remoteVersion; files=$files; releaseTag=$update.releaseTag})
    } catch {
        $prepareErrors++
        Write-Host ($entry.name+': не обновлён. '+$_.Exception.Message)
    }
}
if($candidates.Count -eq 0) { Write-Host 'Нет готовых обновлений. Файлы плеера не изменены.'; exit 1 }
$compatExe=if(Test-Path -LiteralPath (Join-Path $preparedPlayer 'mpv+.exe')) {Join-Path $preparedPlayer 'mpv+.exe'} else {Join-Path $PlayerRoot 'mpv+.exe'}
Report-Progress 'validating'
& (Join-Path $PSScriptRoot 'Test-Extensions.ps1') -Executable $compatExe -ConfigRoot $preparedConfig
$smoke=Join-Path $work 'smoke.lua'
Write-Utf8 $smoke "mp.add_timeout(2,function() print('MPV_BUILD_OK'); mp.commandv('quit') end)"
$stdout=Join-Path $work 'smoke-stdout.txt'
$stderr=Join-Path $work 'smoke-stderr.txt'
$arguments=@(('--config-dir="'+$preparedConfig+'"'),'--idle=yes','--vo=null','--ao=null','--terminal=yes','--msg-level=all=warn,smoke=info',('--script="'+$smoke+'"'))
$process=Start-Process -FilePath $compatExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$null=$process.Handle
if(!$process.WaitForExit(30000)) { $process.Kill(); throw 'Проверка запуска превысила 30 секунд. Установленные файлы не изменены.' }
$process.WaitForExit()
$output=[IO.File]::ReadAllText($stdout)+[IO.File]::ReadAllText($stderr)
if($process.ExitCode -ne 0 -or $output -notmatch 'MPV_BUILD_OK' -or $output -match 'Lua error|stack traceback|Error loading|cannot open') {
    throw "Проверка подготовленной сборки не прошла. Установленные файлы не изменены. Материалы: $work"
}
if($Mode -eq 'Verify') { Write-Host 'Проверено: загрузка релиза, контрольная сумма, сохранение доработок и запуск скриптов. Установка не выполнялась.'; exit 0 }
Assert-PlayerClosed $exe
Report-Progress 'installing'
$originalManifest=[IO.File]::ReadAllBytes($manifestPath)
$undo=New-Object Collections.ArrayList
try {
    foreach($candidate in $candidates) {
        $entry=$candidate.entry
        $destRoot=if($entry.scope -eq 'player') {$PlayerRoot} else {$ConfigRoot}
        $srcRoot=if($entry.scope -eq 'player') {$preparedPlayer} else {$preparedConfig}
        foreach($rel in $candidate.files) {
            $dest=Join-Path $destRoot $rel
            $existed=Test-Path -LiteralPath $dest
            $original=$null
            if($existed) { $original=[IO.File]::ReadAllBytes($dest) }
            [void]$undo.Add(@{path=$dest; content=$original; existed=$existed})
            [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
            Copy-Item -LiteralPath (Join-Path $srcRoot $rel) -Destination $dest -Force
        }
        $entry.version=$candidate.version
        if($entry.kind -in @('mpv','ffmpeg')) {
            $entry | Add-Member -MemberType NoteProperty -Name releaseTag -Value $candidate.releaseTag -Force
        }
        $entry.installedHash=(Get-FileHash -LiteralPath (Join-Path $destRoot $entry.path) -Algorithm SHA256).Hash
        if($entry.kind -eq 'uosc') {
            $hashes=@{}
            foreach($rel in $candidate.files) { $hashes[$rel]=(Get-FileHash -LiteralPath (Join-Path $destRoot $rel) -Algorithm SHA256).Hash }
            $entry.installedFiles=[pscustomobject]$hashes
        }
    }
    Write-Utf8 $manifestPath ($manifest | ConvertTo-Json -Depth 12)
} catch {
    foreach($item in $undo) {
        if($item.existed) { [IO.File]::WriteAllBytes($item.path,[byte[]]$item.content) }
        elseif(Test-Path -LiteralPath $item.path -PathType Leaf) { Remove-Item -LiteralPath $item.path }
    }
    [IO.File]::WriteAllBytes($manifestPath,$originalManifest)
    throw
}
$undo.Clear(); $originalManifest=$null; $original=$null
if(@($candidates | Where-Object {$_.entry.kind -eq 'mpv'}).Count -gt 0) {
    try { & (Join-Path $PSScriptRoot 'Refresh-MPVIcon.ps1') -ExecutablePath (Join-Path $PlayerRoot 'mpv+.exe') -RebuildCache }
    catch { Write-Host 'Значок обновлён в файле. Если Windows показывает старый, повторно войдите в систему.' }
}
Write-Host 'Обновления установлены.'
Report-Progress 'complete'
if($prepareErrors -gt 0 -or $checkErrors -gt 0) { Write-Host 'Часть компонентов пропущена. Причины указаны выше.'; exit 1 }
