param([Parameter(Mandatory=$true)][string]$Executable,[Parameter(Mandatory=$true)][string]$ConfigRoot)
$ErrorActionPreference='Stop'
$test=Join-Path $ConfigRoot 'maintenance\compatibility.lua'
$work=Join-Path $env:TEMP ('mpv-compat-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$log=Join-Path $work 'stdout.txt'
$err=Join-Path $work 'stderr.txt'
$args=@('--no-config','--load-scripts=no','--idle=yes','--vo=null','--ao=null','--terminal=yes',('--config-dir="'+$ConfigRoot+'"'),('--script="'+$test+'"'))
$process=Start-Process -FilePath $Executable -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
$null=$process.Handle
if(!$process.WaitForExit(30000)) { $process.Kill(); throw 'Проверка расширений превысила 30 секунд.' }
$process.WaitForExit()
$output=[IO.File]::ReadAllText($log)+[IO.File]::ReadAllText($err)
if($process.ExitCode -ne 0 -or $output -notmatch 'MPV_EXTENSIONS_OK' -or $output -match 'MPV_EXTENSIONS_FAILED|Lua error|stack traceback') {
    throw "Расширения не прошли проверку. Установка отменена. Отчёт: $work`n$output"
}
# Exercise the native uosc classes, not only the shared Element test double.
$panelTest=Join-Path $ConfigRoot 'maintenance\controls-live-tests.lua'
$args=@('--load-scripts=no','--idle=yes','--vo=null','--ao=null','--terminal=yes',('--config-dir="'+$ConfigRoot+'"'),('--script="'+$panelTest+'"'))
$process=Start-Process -FilePath $Executable -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
$null=$process.Handle
if(!$process.WaitForExit(12000)) { $process.Kill(); throw 'Проверка панели плеера превысила 12 секунд.' }
$process.WaitForExit()
$output=[IO.File]::ReadAllText($log)+[IO.File]::ReadAllText($err)
if($process.ExitCode -ne 0 -or $output -notmatch 'PINNED_PANEL_REAL_UOSC_OK' -or $output -match 'FAILED|Lua error|stack traceback') {
    throw "Панель плеера не прошла проверку: $work`n$output"
}
Write-Host 'Проверено: языки, названия, субтитры, восстановление потока, автообрезка, TorrServer и настоящая панель uosc.'
