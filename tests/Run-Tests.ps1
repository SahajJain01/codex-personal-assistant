#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repository 'personal-assistant/scripts/Assistant.Store.psm1') -Force
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('personal-assistant-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Rejection {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw "Wrong rejection: $($_.Exception.Message); expected $Pattern" }
        return
    }
    throw "Expected rejection: $Pattern"
}
function Convert-TestObject {
    param($Value)
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json
}
function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:passed++
    Write-Output "PASS $Name"
}
function Get-TestConfig {
    $config = Get-Content -LiteralPath (Join-Path $repository 'personal-assistant/assets/config.example.json') -Raw | ConvertFrom-Json
    $config.todoPaths = @((Join-Path $testRoot 'Tasks.md'))
    $config.screenshotFolders = @((Join-Path $testRoot 'screenshots'))
    $config.timezone = 'UTC'
    $config.windowsTimezone = 'UTC'
    if ([DateTime]::UtcNow.Hour -gt 20) { $config.timezone = 'Asia/Bangkok'; $config.windowsTimezone = 'SE Asia Standard Time' }
    $config.taskWindows = @([pscustomobject]@{ start = '00:00'; end = '23:59' })
    $config.breaks = @()
    $config.screenshotSince = [DateTimeOffset]::UtcNow.AddDays(-7).ToString('o')
    return $config
}
function Get-TestTask {
    param([string]$Id = 't-first')
    return [pscustomobject]@{ id = $Id; title = 'Find income statements'; status = 'open'; source = 'Tasks.md / Tax preparation'
        screenshotHash = ''; confidence = 'explicit'; interpretation = ''; parentId = ''; priority = 'Explicit: high'; deadline = ''; nextStep = 'List missing documents'
    }
}
function Get-TestDraft {
    param($State)
    return Convert-TestObject @{ baseRevision = $State.revision; context = $State.context; tasks = @($State.tasks)
        screenshots = @($State.screenshots); questions = @($State.questions); plan = $State.plan; reason = 'Fixture update'
    }
}
function Get-TestPlan {
    param($Config, [string[]]$TaskIds = @('t-first'))
    $date = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, [TimeZoneInfo]::FindSystemTimeZoneById($Config.windowsTimezone)).ToString('yyyy-MM-dd')
    $actions = @()
    foreach ($taskId in $TaskIds) {
        $actions += [pscustomobject]@{ taskId = $taskId; action = 'Find income statements'; doneWhen = 'Missing documents listed'; minutes = 20; startHere = ($actions.Count -eq 0) }
    }
    return [pscustomobject]@{ date = $date; actions = $actions; availableMinutes = 120; questions = @(); markdown = '# Three achievable steps'; calendarFresh = $true }
}
function Invoke-State {
    param([string]$Command, $Request = $null)
    return Invoke-AssistantCommand -Workspace $workspace -Command $Command -RunToken $token -Request (Convert-TestObject $Request)
}

$workspace = Join-Path $testRoot 'workspace'
$token = ''
$config = Get-TestConfig
$initialText = [string][char]0xFEFF + "# Tasks`r`n- [ ] Find income statements`r`n- [ ] Book dentist`r`n"
[IO.File]::WriteAllText($config.todoPaths[0], $initialText, [Text.UTF8Encoding]::new($false))
[void][IO.Directory]::CreateDirectory($config.screenshotFolders[0])
$init = @{ config = $config; context = "# Context`n## Confirmed facts`nPrefers short steps." }

Invoke-TestCase 'Initialize and reinstall preserve private identity and context' {
    $first = Invoke-State Init $init
    $second = Invoke-State Init @{ config = $config; context = 'must not replace memory' }
    Assert-True ($first.installationId -eq $second.installationId -and $first.context -eq $second.context -and $second.revision -eq 1) 'Init was not idempotent.'
}
Invoke-TestCase 'Reject private state inside the distributable repository' {
    Assert-Rejection { Invoke-AssistantCommand -Workspace (Join-Path $repository 'private') -Command Init -Request (Convert-TestObject $init) } 'outside'
}
$state = Invoke-State Begin
$token = $state.activeRun.token
Invoke-TestCase 'Concurrent runs and wrong tokens cannot mutate state' {
    Assert-Rejection { Invoke-State Begin } 'Another run'
    Assert-Rejection { Invoke-AssistantCommand -Workspace $workspace -Command End -RunToken 'wrong' } 'ownership'
    $handle = [IO.File]::Open((Join-Path $workspace '.command.lock'), 'Open', 'ReadWrite', 'None')
    try { Assert-Rejection { Invoke-State Read } 'busy' }
    finally { $handle.Dispose() }
}
Invoke-TestCase 'Commit a bounded actionable plan and reject stale drafts' {
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.tasks = @((Get-TestTask))
    $draft.plan = Get-TestPlan $config
    $saved = Invoke-State Commit $draft
    Assert-True ($saved.tasks.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $workspace 'today.md'))) 'Plan was not persisted.'
    Assert-Rejection { Invoke-State Commit $draft } 'Stale draft'
}
Invoke-TestCase 'Enforce action count, capacity, readiness, and completion conditions' {
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.tasks = @((Get-TestTask 't-first'), (Get-TestTask 't-two'), (Get-TestTask 't-three'), (Get-TestTask 't-four'))
    $draft.plan = Get-TestPlan $config @('t-first', 't-two', 't-three', 't-four')
    Assert-Rejection { Invoke-State Commit $draft } 'cap'
    $draft.plan = Get-TestPlan $config
    $draft.plan.availableMinutes = 20
    Assert-Rejection { Invoke-State Commit $draft } 'capacity'
    $draft.plan.availableMinutes = 120
    $draft.tasks[0].status = 'needs_context'
    Assert-Rejection { Invoke-State Commit $draft } 'actionable'
    $draft.tasks[0].status = 'open'
    $draft.plan.actions[0].doneWhen = ''
    Assert-Rejection { Invoke-State Commit $draft } 'completion condition'
}
Invoke-TestCase 'Duplicate screenshots process once, with immutable observations' {
    $imageBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
    foreach ($name in 'one.png', 'renamed-copy.png') {
        $path = Join-Path $config.screenshotFolders[0] $name
        [IO.File]::WriteAllBytes($path, $imageBytes)
        [IO.File]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddMinutes(-2))
    }
    $new = @(Invoke-State Discover)
    Assert-True ($new.Count -eq 1) 'Renamed duplicate was not deduplicated.'
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.screenshots = @([pscustomobject]@{ hash = $new[0].hash; path = $new[0].path; observation = 'Solid pixel'; visibleDates = @(); outcome = 'no_action' })
    [void](Invoke-State Commit $draft)
    Assert-True (@(Invoke-State Discover).Count -eq 0) 'Committed image was offered again.'
    $jsonResult = & (Join-Path $repository 'personal-assistant/scripts/Assistant.ps1') -Workspace $workspace -Command Discover -RunToken $token
    Assert-True ($jsonResult.Trim() -match '^\[\s*\]$') "CLI must return an empty JSON array, not null: $jsonResult"
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.screenshots[0].observation = 'Invented obligation'
    Assert-Rejection { Invoke-State Commit $draft } 'immutable'
}
Invoke-TestCase 'Changed bytes are new; unavailable folders and syncing files do not erase state' {
    $path = Join-Path $config.screenshotFolders[0] 'one.png'
    [IO.File]::WriteAllBytes($path, [byte[]](1, 2, 3, 4))
    Assert-True (@(Invoke-State Discover).Count -eq 0) 'Actively syncing file was processed.'
    [IO.File]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddMinutes(-2))
    Assert-True (@(Invoke-State Discover).Count -eq 1) 'Changed bytes were not rediscovered.'
    $changed = Convert-TestObject $config
    $changed.screenshotFolders += Join-Path $testRoot 'missing-folder'
    [void](Invoke-State Configure @{ config = $changed })
    $found = @(Invoke-State Discover)
    Assert-True (@($found | Where-Object { $_.status -eq 'unavailable' }).Count -eq 1) 'Missing folder was hidden.'
    [void](Invoke-State Configure @{ config = $config })
}
Invoke-TestCase 'Clarification reuses task identity and preserves question history' {
    $draft = Get-TestDraft (Invoke-State Read)
    $task = Get-TestTask 't-candidate'
    $task.status = 'needs_context'; $task.confidence = 'low'; $task.interpretation = 'Possible reminder'
    $draft.tasks += $task
    $draft.questions = @([pscustomobject]@{ id = 'q-intent'; text = 'Is this an action or reference?'; taskId = $task.id; status = 'open'; answer = ''; lastAskedAt = ''; revisitAfter = '' })
    [void](Invoke-State Commit $draft)
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.tasks[1].status = 'dismissed'; $draft.tasks[1].interpretation = 'User: just inspiration'
    $draft.questions[0].status = 'answered'; $draft.questions[0].answer = 'Just inspiration'
    $saved = Invoke-State Commit $draft
    Assert-True ($saved.tasks.Count -eq 2 -and $saved.tasks[1].id -eq 't-candidate') 'Clarification duplicated the task.'
    $draft = Get-TestDraft $saved; $draft.questions = @()
    Assert-Rejection { Invoke-State Commit $draft } 'question history'
}
Invoke-TestCase 'Explicit progress persists and patches only one UTF-8 source byte' {
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.tasks[0].status = 'done'; $draft.plan.actions = @()
    [void](Invoke-State Commit $draft)
    $request = @{ path = $config.todoPaths[0]; expectedHash = (Get-FileHash -LiteralPath $config.todoPaths[0]).Hash.ToLowerInvariant()
        lineNumber = 2; expectedLine = '- [ ] Find income statements'; taskId = 't-first'; userReport = 'I finished finding income statements'
    }
    [void](Invoke-State CompleteSource $request)
    $after = [IO.File]::ReadAllText($config.todoPaths[0], [Text.UTF8Encoding]::new($false))
    Assert-True ($after -eq $initialText.TrimStart([char]0xFEFF).Replace('- [ ] Find', '- [x] Find')) 'Surrounding source text changed.'
    $bytes = [IO.File]::ReadAllBytes($config.todoPaths[0])
    Assert-True ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'UTF-8 BOM lost.'
    Assert-Rejection { Invoke-State CompleteSource $request } 'Source changed'
}
Invoke-TestCase 'Recovery rebuilds damaged views without losing committed progress' {
    [IO.File]::WriteAllText((Join-Path $workspace 'today.md'), 'partial projection')
    $saved = Invoke-State Recover @{ abandonRun = $false }
    Assert-True ((Get-Content -LiteralPath (Join-Path $workspace 'today.md') -Raw) -eq $saved.plan.markdown) 'Projection did not recover.'
    Assert-True ($saved.tasks[0].status -eq 'done') 'Recovery resurrected completed work.'
}
Invoke-TestCase 'Interrupted source preparation reconciles without rewriting user data' {
    $draft = Get-TestDraft (Invoke-State Read)
    $task = Get-TestTask 't-source-recovery'; $task.status = 'done'; $task.title = 'Book dentist'
    $draft.tasks += $task
    [void](Invoke-State Commit $draft)
    $request = @{ path = $config.todoPaths[0]; expectedHash = (Get-FileHash -LiteralPath $config.todoPaths[0]).Hash.ToLowerInvariant()
        lineNumber = 3; expectedLine = '- [ ] Book dentist'; taskId = $task.id; userReport = 'I booked the dentist'
    }
    $viewLock = [IO.File]::Open((Join-Path $workspace 'today.md'), 'Open', 'ReadWrite', 'None')
    try { Assert-Rejection { Invoke-State CompleteSource $request } 'Replace|access|process' }
    finally { $viewLock.Dispose() }
    $saved = Invoke-State Read
    Assert-True ($saved.sourceOperations[-1].status -eq 'pending') 'Interrupted preparation was not journaled.'
    $reconciled = Invoke-State ReconcileSource @{ operationId = $saved.sourceOperations[-1].id }
    Assert-True ($reconciled.sourceOperations[-1].status -eq 'not_applied') 'Source unchanged result was not recognized.'
    Assert-True ((Get-Content -LiteralPath $config.todoPaths[0] -Raw).Contains('- [ ] Book dentist')) 'Reconciliation rewrote source.'
}
Invoke-TestCase 'Interrupted context rendering does not roll back committed memory on next run' {
    $draft = Get-TestDraft (Invoke-State Read); $draft.context = '# New committed preference'
    $viewLock = [IO.File]::Open((Join-Path $workspace 'context.md'), 'Open', 'ReadWrite', 'None')
    try { Assert-Rejection { Invoke-State Commit $draft } 'Replace|access|process' }
    finally { $viewLock.Dispose() }
    # Simulate the old process ending without its normal End command.
    [void](Invoke-State Recover @{ abandonRun = $true; reason = 'Fixture process stopped after a rendering failure' })
    $newRun = Invoke-State Begin
    Assert-True ($newRun.context -eq '# New committed preference') 'Stale projection replaced committed context.'
    $script:token = $newRun.activeRun.token
}

# Simulated connector boundary: assertions exercise operation protocol, not Google itself.
$draft = Get-TestDraft (Invoke-State Read)
$draft.tasks += Get-TestTask 't-calendar'
$draft.plan = Get-TestPlan $config @('t-calendar')
[void](Invoke-State Commit $draft)
$start = [DateTimeOffset]::UtcNow.AddMinutes(5)
$create = @{ action = 'create'; taskId = 't-calendar'; date = $draft.plan.date; calendarId = 'primary'
    checkedAt = [DateTimeOffset]::UtcNow.ToString('o'); calendarComplete = $true; busy = @(); before = $null
    desired = @{ title = 'Find income statements'; description = 'Done when missing documents are listed'; start = $start.ToString('o'); end = $start.AddMinutes(20).ToString('o') }
}
Invoke-TestCase 'Calendar rejects stale reads and overlaps before an operation is saved' {
    $bad = Convert-TestObject $create; $bad.checkedAt = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
    Assert-Rejection { Invoke-State PrepareCalendar $bad } 'Refresh'
    $bad = Convert-TestObject $create; $bad.busy = @(@{ start = $start.ToString('o'); end = $start.AddMinutes(10).ToString('o') })
    Assert-Rejection { Invoke-State PrepareCalendar $bad } 'conflicts'
}
$state = Invoke-State PrepareCalendar $create
$operation = $state.calendarOperations[-1]
$arguments = $operation.connectorArguments
$observed = @{ id = 'fixture-event'; calendarId = 'primary'; title = $arguments.title; description = $arguments.description
    start = $arguments.start_time; end = $arguments.end_time; visibility = 'private'; transparency = 'opaque'; attendees = @()
    recurrence = @(); reminders = @{ use_default = $false; overrides = @() }; meet = ''; eventType = 'default'
}
Invoke-TestCase 'Prepared calendar calls are private solo blocks and block duplicate retries' {
    Assert-True (-not $arguments.add_google_meet -and $arguments.attendees.Count -eq 0 -and $arguments.visibility -eq 'private') 'Unsafe calendar arguments.'
    Assert-Rejection { Invoke-State PrepareCalendar $create } 'unresolved'
    [void](Invoke-State CompleteCalendar @{ operationId = $operation.id; outcome = 'uncertain'; event = $null; evidence = 'Simulated response timeout' })
    Assert-Rejection { Invoke-State PrepareCalendar $create } 'unresolved'
    [void](Invoke-State CompleteCalendar @{ operationId = $operation.id; outcome = 'applied'; event = $observed; evidence = 'Simulated fresh read found exact ownership marker once' })
    Assert-True (@((Invoke-State Read).blocks).Count -eq 1) 'Response-loss reconciliation failed.'
    Assert-Rejection { Invoke-State PrepareCalendar $create } 'duplicate'
}
Invoke-TestCase 'User-moved calendar block becomes an override and cannot be overwritten' {
    $moved = Convert-TestObject $observed
    $moved.start = $start.AddMinutes(60).ToString('o'); $moved.end = $start.AddMinutes(80).ToString('o')
    $update = Convert-TestObject $create; $update.action = 'update'; $update.before = $moved
    $saved = Invoke-State PrepareCalendar $update
    Assert-True ($saved.blocks[0].status -eq 'user_override' -and $saved.calendarOperations.Count -eq 1) 'User move did not prevent mutation.'
    Assert-Rejection { Invoke-State PrepareCalendar $update } 'override'
}
Invoke-TestCase 'Create, update, delete, and recreate an assistant-owned block safely' {
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.tasks += Get-TestTask 't-lifecycle'
    $draft.plan = Get-TestPlan $config @('t-lifecycle')
    [void](Invoke-State Commit $draft)
    $request = Convert-TestObject $create; $request.taskId = 't-lifecycle'
    $saved = Invoke-State PrepareCalendar $request
    $operationId = $saved.calendarOperations[-1].id
    $remote = Convert-TestObject $observed
    $remote.id = 'fixture-lifecycle'; $remote.description = $saved.calendarOperations[-1].connectorArguments.description
    [void](Invoke-State CompleteCalendar @{ operationId = $operationId; outcome = 'applied'; event = $remote; evidence = 'Simulated create readback' })
    $request.action = 'update'; $request.before = $remote
    $request.desired.start = $start.AddMinutes(30).ToString('o'); $request.desired.end = $start.AddMinutes(50).ToString('o')
    $saved = Invoke-State PrepareCalendar $request
    $operationId = $saved.calendarOperations[-1].id
    $remote.start = $request.desired.start; $remote.end = $request.desired.end
    [void](Invoke-State CompleteCalendar @{ operationId = $operationId; outcome = 'applied'; event = $remote; evidence = 'Simulated update readback' })
    $request.action = 'delete'; $request.before = $remote; $request.desired = $null
    $saved = Invoke-State PrepareCalendar $request
    $operationId = $saved.calendarOperations[-1].id
    Assert-True ($saved.calendarOperations[-1].connectorArguments.event_id -eq $remote.id) 'Deletion target is not owned.'
    [void](Invoke-State CompleteCalendar @{ operationId = $operationId; outcome = 'applied'; event = $null; evidence = 'Simulated confirmed 404 after delete' })
    $request = Convert-TestObject $create; $request.taskId = 't-lifecycle'
    $saved = Invoke-State PrepareCalendar $request
    Assert-True ($saved.calendarOperations[-1].action -eq 'create') 'Assistant-removed block cannot be rescheduled.'
    [void](Invoke-State CompleteCalendar @{ operationId = $saved.calendarOperations[-1].id; outcome = 'not_applied'; event = $null; evidence = 'Fixture did not dispatch connector call' })
}
Invoke-TestCase 'Calendar outage and foreign calendar cannot produce writes' {
    $draft = Get-TestDraft (Invoke-State Read)
    $draft.plan.calendarFresh = $false
    [void](Invoke-State Commit $draft)
    $request = Convert-TestObject $create; $request.taskId = 't-lifecycle'
    Assert-Rejection { Invoke-State PrepareCalendar $request } 'fresh calendar'
    $request.calendarId = 'foreign-calendar'
    Assert-Rejection { Invoke-State PrepareCalendar $request } 'write target'
}
Invoke-TestCase 'Schedule reconciliation preserves exactly two IDs across setup reruns' {
    $schedules = @(
        @{ kind = 'morning'; id = 'fixture-morning'; threadId = 'fixture-thread'; prompt = 'Morning fixture'; status = 'ACTIVE' },
        @{ kind = 'monitor'; id = 'fixture-monitor'; threadId = 'fixture-thread'; prompt = 'Monitor fixture'; status = 'ACTIVE' })
    [void](Invoke-State Schedules @{ schedules = $schedules })
    [void](Invoke-State Schedules @{ schedules = $schedules })
    Assert-True ((Invoke-State Read).schedules.Count -eq 2) 'Schedule IDs duplicated.'
}
Invoke-TestCase 'Ended and abandoned runs reject their old tokens' {
    [void](Invoke-State End)
    Assert-Rejection { Invoke-State Renew } 'ownership'
    $next = Invoke-State Begin
    [void](Invoke-State Recover @{ abandonRun = $true; reason = 'Fixture has no active connector process' })
    Assert-Rejection { Invoke-AssistantCommand -Workspace $workspace -Command Renew -RunToken $next.activeRun.token } 'ownership'
}
Invoke-TestCase 'Isolated plugin installation is repeatable and preserves unrelated entries' {
    $testProfile = Join-Path $testRoot 'profile'
    $marketplaceDirectory = Join-Path $testProfile '.agents/plugins'
    [void][IO.Directory]::CreateDirectory($marketplaceDirectory)
    $marketplace = @{ name = 'personal'; interface = @{ displayName = 'My tools' }; plugins = @(@{ name = 'unrelated'; source = @{ source = 'local'; path = './plugins/unrelated' } }) }
    $marketplacePath = Join-Path $marketplaceDirectory 'marketplace.json'
    [IO.File]::WriteAllText($marketplacePath, ($marketplace | ConvertTo-Json -Depth 10))
    & (Join-Path $repository 'tools/Install.ps1') -ProfileRoot $testProfile -RegisterOnly | Out-Null
    & (Join-Path $repository 'tools/Install.ps1') -ProfileRoot $testProfile -RegisterOnly | Out-Null
    $installed = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
    Assert-True ($installed.plugins.Count -eq 2 -and $installed.interface.displayName -eq 'My tools') 'Install damaged marketplace or duplicated plugin.'
    Assert-True (Test-Path -LiteralPath (Join-Path $testProfile 'plugins/personal-assistant/skills/assistant-run/SKILL.md')) 'Packaged skill missing.'
}
Write-Output "Passed $script:passed scenarios. Evidence retained at $testRoot"
