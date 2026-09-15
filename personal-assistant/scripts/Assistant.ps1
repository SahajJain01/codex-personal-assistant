#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][ValidateSet('Init', 'Read', 'Begin', 'Renew', 'End', 'Discover', 'Commit',
        'Recover', 'Configure', 'Schedules', 'PrepareCalendar', 'DispatchCalendar', 'CompleteCalendar', 'Override', 'CompleteSource', 'ReconcileSource')][string]$Command,
    [string]$RequestPath,
    [string]$RunToken
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSScriptRoot 'Assistant.Store.psm1') -Force
$request = $null
if ($RequestPath) { $request = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RequestPath)) | ConvertFrom-Json }
if ($Command -eq 'Discover') {
    $result = @(Invoke-AssistantCommand -Workspace $Workspace -Command $Command -Request $request -RunToken $RunToken)
}
else {
    $result = Invoke-AssistantCommand -Workspace $Workspace -Command $Command -Request $request -RunToken $RunToken
}
ConvertTo-Json -InputObject $result -Depth 100
