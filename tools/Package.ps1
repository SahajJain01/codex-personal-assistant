#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content -LiteralPath (Join-Path $root 'personal-assistant/release.json') -Raw | ConvertFrom-Json
$output = Join-Path $root 'dist'
[void][IO.Directory]::CreateDirectory($output)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $output "hermes-personal-assistant-$($manifest.version).zip"
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
$staging = Join-Path ([IO.Path]::GetTempPath()) ('personal-assistant-release-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($staging)
foreach ($name in 'personal-assistant', 'tools', 'tests', 'docs', 'README.md', 'BOOTSTRAP.md', 'AGENTS.md') {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $name) -Recurse -File) {
        if ($file.FullName -match '[\\/]__pycache__[\\/]' -or $file.Extension -notin '.md', '.json', '.ps1', '.psm1', '.py') { continue }
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        $targetFile = Join-Path $staging $relative
        [void][IO.Directory]::CreateDirectory((Split-Path $targetFile -Parent))
        Copy-Item -LiteralPath $file.FullName -Destination $targetFile
    }
}
[IO.Compression.ZipFile]::CreateFromDirectory($staging, $archive)
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    if (@($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq 'personal-assistant/SKILL.md' }).Count -ne 1) {
        throw 'Release is missing the Hermes skill.'
    }
}
finally { $zip.Dispose() }
Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Select-Object Path, Hash
