#Requires -Version 5.1
[CmdletBinding()]
param([string]$HermesHome)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This release supports Windows only.' }
if (-not $HermesHome) {
    if ($env:HERMES_HOME) { $HermesHome = $env:HERMES_HOME }
    else { $HermesHome = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hermes' }
}
$targetRoot = [IO.Path]::GetFullPath($HermesHome).TrimEnd('\')
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'personal-assistant'
$release = Get-Content -LiteralPath (Join-Path $source 'release.json') -Raw | ConvertFrom-Json
if ($release.host -ne 'hermes' -or $release.name -ne 'personal-assistant') { throw 'Unexpected release identity.' }
$parent = Join-Path $targetRoot 'skills/productivity'
$destination = Join-Path $parent 'personal-assistant'
$maintenance = Join-Path $targetRoot 'assistant-releases'
[void][IO.Directory]::CreateDirectory($parent)
[void][IO.Directory]::CreateDirectory($maintenance)
$installLock = [IO.File]::Open((Join-Path $maintenance 'install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    if (Test-Path -LiteralPath $destination) {
        $marker = Join-Path $destination 'release.json'
        if (-not (Test-Path -LiteralPath $marker)) { throw 'Existing skill is not owned by this installer.' }
        $old = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
        if ($old.name -ne $release.name -or $old.host -ne 'hermes') { throw 'Existing skill has a different owner.' }
    }
    $staging = Join-Path $maintenance ('stage-' + [guid]::NewGuid().ToString('N'))
    $backup = Join-Path $maintenance ('backup-' + [guid]::NewGuid().ToString('N'))
    foreach ($target in @($destination, $staging, $backup)) {
        if (-not [IO.Path]::GetFullPath($target).StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Installation target escapes Hermes profile.'
        }
        if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Installation target must not be a junction or symbolic link.'
        }
    }
    [void][IO.Directory]::CreateDirectory($staging)
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
        if ($file.Extension -notin '.md', '.json', '.ps1', '.psm1', '.py' -or $file.FullName -match '[\\/]__pycache__[\\/]') { continue }
        $relative = $file.FullName.Substring($source.Length).TrimStart('\')
        $targetFile = Join-Path $staging $relative
        [void][IO.Directory]::CreateDirectory((Split-Path $targetFile -Parent))
        Copy-Item -LiteralPath $file.FullName -Destination $targetFile
    }
    if (Test-Path -LiteralPath $destination) { Move-Item -LiteralPath $destination -Destination $backup }
    try { Move-Item -LiteralPath $staging -Destination $destination }
    catch {
        if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $destination)) {
            Move-Item -LiteralPath $backup -Destination $destination
        }
        throw
    }
}
finally { $installLock.Dispose() }
[pscustomobject]@{ skill = $release.name; version = $release.version; path = $destination
    next = 'In Hermes, load personal-assistant and follow setup. No schedules or accounts were changed.'
} | ConvertTo-Json
