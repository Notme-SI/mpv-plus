$ErrorActionPreference='Stop'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$work=Join-Path $env:TEMP ('mpv-updater-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$exe=Join-Path $work 'tests.exe'
& $compiler /nologo /target:exe /main:UpdaterTests /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll ('/out:'+$exe) (Join-Path $PSScriptRoot Updater.cs) (Join-Path $PSScriptRoot Updater.Tests.cs)
if($LASTEXITCODE -ne 0) { throw 'Native updater compilation failed' }
& $exe
if($LASTEXITCODE -ne 0) { throw 'Native updater checks failed' }
