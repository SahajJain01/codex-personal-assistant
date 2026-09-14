#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Fix)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $root '.tools/PSScriptAnalyzer/1.24.0/PSScriptAnalyzer.psd1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw 'Run Save-Module -Name PSScriptAnalyzer -RequiredVersion 1.24.0 -Path .tools -Repository PSGallery first.'
}
Import-Module $modulePath
$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension -in '.ps1', '.psm1' -and $_.FullName -notmatch '[\\/](\.tools|\.test-output|dist)[\\/]'
}
$problems = @()
foreach ($file in $files) {
    $original = [IO.File]::ReadAllText($file.FullName)
    $formatted = Invoke-Formatter -ScriptDefinition $original -Settings CodeFormatting
    # PSScriptAnalyzer can leave spaces before a closing hashtable newline.
    $formatted = [regex]::Replace($formatted, '(?m)[ \t]+(?=\r?$)', '')
    if ($original.TrimEnd() -cne $formatted.TrimEnd()) {
        if ($Fix) { [IO.File]::WriteAllText($file.FullName, $formatted, [Text.UTF8Encoding]::new($false)) }
        else { $problems += "Formatting: $($file.FullName)" }
    }
    $problems += @(Invoke-ScriptAnalyzer -Path $file.FullName -Severity Warning, Error)
}
if ($problems.Count) { $problems | Out-String | Write-Output; throw 'Quality checks failed.' }
Write-Output "Formatting and static analysis passed for $($files.Count) PowerShell files."
