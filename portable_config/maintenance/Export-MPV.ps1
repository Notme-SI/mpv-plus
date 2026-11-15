param([string]$OutputDirectory=(Join-Path $env:USERPROFILE 'Downloads'),[string]$SettingsDirectory,[string]$ReportPath,[string]$PlayerDirectory)
$ErrorActionPreference='Stop'
$config=Split-Path -Parent $PSScriptRoot
$player=if($PlayerDirectory){(Resolve-Path -LiteralPath $PlayerDirectory).Path}else{Split-Path -Parent $config}
$exe=Join-Path $player 'mpv+.exe'
if(!(Test-Path -LiteralPath $exe)) {throw 'mpv+.exe is missing.'}
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$zip=Join-Path $OutputDirectory ('mpv+-Backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
$files=@{}
Get-ChildItem -LiteralPath $player -File -Recurse -Force | ForEach-Object {
    $rel=$_.FullName.Substring($player.Length+1)
    if($rel -notmatch '(^|\\)(uninstall|watch_later|watch_history)(\\|$)' -and $rel -notmatch '\.(cmd|bat|bak|log)$') {$files[$rel]=$_.FullName}
}
if($SettingsDirectory -and (Test-Path -LiteralPath $SettingsDirectory)) {
    Get-ChildItem -LiteralPath $SettingsDirectory -File -Recurse | ForEach-Object {
        $rel=$_.FullName.Substring($SettingsDirectory.TrimEnd('\').Length+1)
        if($rel -notmatch '(^|\\)(watch_later|watch_history)(\\|$)') {$files['portable_config\'+$rel]=$_.FullName}
    }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
try {foreach($rel in $files.Keys) {
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$files[$rel],('mpv+-Portable/'+$rel.Replace('\','/')),[IO.Compression.CompressionLevel]::Optimal)|Out-Null
}} finally {$archive.Dispose()}
if($ReportPath) {[IO.File]::WriteAllText($ReportPath,(@{path=$zip}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
Write-Output $zip
