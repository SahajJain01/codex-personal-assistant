#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ProfileRoot = [Environment]::GetFolderPath('UserProfile'),
    [switch]$RegisterOnly
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This release supports Windows only.' }
$repository = Split-Path $PSScriptRoot -Parent
$source = Join-Path $repository 'personal-assistant'
$manifest = Get-Content -LiteralPath (Join-Path $source '.codex-plugin/plugin.json') -Raw | ConvertFrom-Json
if ($manifest.name -ne 'personal-assistant') { throw 'Unexpected plugin identity.' }
$profilePath = [IO.Path]::GetFullPath($ProfileRoot).TrimEnd('\')
$pluginParent = Join-Path $profilePath 'plugins'
$destination = Join-Path $pluginParent 'personal-assistant'
$marketplacePath = Join-Path $profilePath '.agents/plugins/marketplace.json'
[void][IO.Directory]::CreateDirectory((Split-Path $marketplacePath -Parent))
[void][IO.Directory]::CreateDirectory($pluginParent)

Import-Module (Join-Path $source 'scripts/Assistant.Store.psm1') -Force
$marketplaceLock = [IO.File]::Open("$marketplacePath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
try {
    if (Test-Path -LiteralPath $marketplacePath) {
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
        if ($marketplace.name -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid existing marketplace name.' }
    }
    else {
        $marketplace = [pscustomobject]@{ name = 'personal'; interface = @{ displayName = 'Personal' }; plugins = @() }
    }
    $existing = @($marketplace.plugins | Where-Object { $_.name -eq $manifest.name })
    if ($existing.Count -gt 1 -or ($existing.Count -and ($existing[0].source.path -ne './plugins/personal-assistant' -or $existing[0].source.source -ne 'local'))) {
        throw 'An existing plugin entry points elsewhere. Resolve that installation before replacing it.'
    }

    # Prepare the complete release before replacing the installed source. Preserve the old release.
    $staging = Join-Path $pluginParent ('.personal-assistant-stage-' + [guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $source -Destination $staging -Recurse
    if (Test-Path -LiteralPath $destination) {
        $backup = Join-Path $pluginParent ('.personal-assistant-backup-' + [guid]::NewGuid().ToString('N'))
        foreach ($target in @($destination, $backup)) {
            if (-not [IO.Path]::GetFullPath($target).StartsWith($pluginParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Installation target escapes plugin directory.'
            }
        }
        Move-Item -LiteralPath $destination -Destination $backup
    }
    Move-Item -LiteralPath $staging -Destination $destination
    if (-not $existing.Count) {
        $entry = [pscustomobject]@{ name = $manifest.name; source = @{ source = 'local'; path = './plugins/personal-assistant' }
            policy = @{ installation = 'AVAILABLE'; authentication = 'ON_INSTALL' }; category = 'Productivity'
        }
        $marketplace.plugins = @($marketplace.plugins) + @($entry)
        $json = $marketplace | ConvertTo-Json -Depth 30
        $temporary = "$marketplacePath.tmp"
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $marketplacePath) { [IO.File]::Replace($temporary, $marketplacePath, "$marketplacePath.bak") }
        else { [IO.File]::Move($temporary, $marketplacePath) }
    }
}
finally { $marketplaceLock.Dispose() }

if (-not $RegisterOnly) {
    if ($profilePath -ne [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile')).TrimEnd('\')) {
        throw 'Use RegisterOnly for an isolated test profile.'
    }
    & codex plugin add "$($manifest.name)@$($marketplace.name)"
    if ($LASTEXITCODE -ne 0) { throw 'Plugin registered, but Codex installation failed. Re-run after resolving the reported error.' }
}
[pscustomobject]@{ plugin = $manifest.name; path = $destination; marketplace = $marketplacePath
    installed = -not $RegisterOnly; next = 'Open a Codex task in your private workspace and invoke Assistant setup.'
} | ConvertTo-Json
