$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'portable_config/maintenance/Update-MPV.ps1') -Library
function Assert([bool]$Condition,[string]$Message) { if(!$Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action) {
    $rejected=$false
    try { & $Action | Out-Null } catch {
        if($_.Exception.Message -notlike 'Исходник изменился*') { throw }
        $rejected=$true
    }
    Assert $rejected 'An incompatible or ambiguous source must be rejected'
}
$source=Get-Content (Join-Path $root 'SOURCES/upstream/theintrodb.lua') -Raw -Encoding UTF8
$patches=Get-Content (Join-Path $root 'portable_config/maintenance/patches/TheIntroDB.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$installed=Get-Content (Join-Path $root 'portable_config/scripts/theintrodb.lua') -Raw -Encoding UTF8
$patched=Apply-Patches $source $patches
Assert ($patched -ceq (Normalize $installed)) 'The pinned upstream plus patches must reproduce the installed script'
$manifest=Get-Content (Join-Path $root 'portable_config/maintenance/manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$entry=$manifest.entries | Where-Object name -eq 'TheIntroDB'
$hash=(Get-FileHash (Join-Path $root 'portable_config/scripts/theintrodb.lua') -Algorithm SHA256).Hash
Assert ($hash -eq $entry.installedHash) 'The manifest must match the shipped script'
$utf8=New-Object Text.UTF8Encoding($false)
$bytes=$utf8.GetBytes((Normalize $source))
$blob=$utf8.GetBytes(('blob '+$bytes.Length)+[char]0)+$bytes
$sha=[Security.Cryptography.SHA1]::Create()
try { $blobHash=([BitConverter]::ToString($sha.ComputeHash($blob))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
Assert ($blobHash -eq $entry.version) 'The manifest must pin the original Git blob'
Assert ((Apply-Patches ($source.Replace("`n","`r`n")) $patches) -ceq $patched) 'Windows line endings must remain supported'
$newVersion=$source.Replace('-- version: v2.1.0','-- version: v2.1.1')+"-- unrelated upstream addition`n"
$expected=$patched.Replace('-- version: v2.1.0','-- version: v2.1.1')+"-- unrelated upstream addition`n"
Assert ((Apply-Patches $newVersion $patches) -ceq $expected) 'Unrelated upstream changes must survive patching'
$first=[string]$patches[0].before
Assert-Rejected { Apply-Patches ($source.Replace($first,'-- conflicting upstream description')) $patches }
Assert-Rejected { Apply-Patches ($source+$first) $patches }
Write-Host 'UPDATER_PATCHES_OK'
