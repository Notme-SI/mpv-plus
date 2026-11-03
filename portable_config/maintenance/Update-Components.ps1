param([int]$WaitProcessId,[string]$ResultPath,[switch]$Elevated,[switch]$Visible)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$updater=Join-Path $PSScriptRoot 'mpv-update.exe'
if(!(Test-Path -LiteralPath $updater)) { throw 'mpv-update.exe is missing. Reinstall the full mpv+ package.' }
Start-Process -FilePath $updater -ArgumentList @('--root',('"'+$root+'"'),'--pid',[string]$WaitProcessId,'--view','components') -WindowStyle Hidden
