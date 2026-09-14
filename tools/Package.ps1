#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content -LiteralPath (Join-Path $root 'personal-assistant/.codex-plugin/plugin.json') -Raw | ConvertFrom-Json
$output = Join-Path $root 'dist'
[void][IO.Directory]::CreateDirectory($output)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $output "personal-assistant-$($manifest.version).zip"
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
$staging = Join-Path ([IO.Path]::GetTempPath()) ('personal-assistant-release-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($staging)
foreach ($name in 'personal-assistant', 'tools', 'tests', 'docs', 'README.md', 'BOOTSTRAP.md', 'AGENTS.md') {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $staging -Recurse -Force
}
[IO.Compression.ZipFile]::CreateFromDirectory($staging, $archive)
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    if (@($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq 'personal-assistant/.codex-plugin/plugin.json' }).Count -ne 1) {
        throw 'Release is missing the plugin manifest.'
    }
}
finally { $zip.Dispose() }
Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Select-Object Path, Hash
