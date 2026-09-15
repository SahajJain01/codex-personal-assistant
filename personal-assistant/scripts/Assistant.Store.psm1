#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TextHash {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $algorithm.Dispose() }
}

function Write-AtomicText {
    param([string]$Path, [string]$Text)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [IO.File]::Open($temporary, 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, "$Path.bak") }
    else { [IO.File]::Move($temporary, $Path) }
}

function Assert-RequiredField {
    param($Value, [string[]]$Fields)
    foreach ($field in $Fields) {
        if ($null -eq $Value -or $field -notin $Value.PSObject.Properties.Name) {
            throw "Missing field: $field"
        }
    }
}

function Assert-Config {
    param($Config)
    Assert-RequiredField $Config @('schemaVersion', 'todoPaths', 'screenshotFolders', 'calendarIds', 'writeCalendarId',
        'timezone', 'windowsTimezone', 'morningTime', 'monitorStart', 'monitorEnd', 'planningDays',
        'taskWindows', 'breaks', 'maxActions', 'capacityFraction', 'preferredActionMinutes',
        'screenshotSince', 'sourceCheckboxWrites', 'calendarWrites')
    if ($Config.schemaVersion -ne 1) { throw 'Unsupported configuration version.' }
    foreach ($field in 'sourceCheckboxWrites', 'calendarWrites') {
        if ($Config.$field -isnot [bool]) { throw "$field must be a JSON boolean." }
    }
    if ($Config.maxActions -lt 1 -or $Config.maxActions -gt 3) { throw 'maxActions must be 1..3.' }
    if ($Config.capacityFraction -le 0 -or $Config.capacityFraction -gt 0.6) { throw 'capacityFraction must be >0 and <=0.6.' }
    if ($Config.preferredActionMinutes -lt 15 -or $Config.preferredActionMinutes -gt 60) { throw 'Action minutes must be 15..60.' }
    if (@($Config.calendarIds).Count -eq 0 -or $Config.writeCalendarId -notin $Config.calendarIds) {
        throw 'Include the writable calendar in calendarIds.'
    }
    if (@($Config.planningDays).Count -eq 0) { throw 'Select at least one planning day.' }
    foreach ($day in $Config.planningDays) {
        if ($day -notin @('MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU')) { throw 'Invalid planning day.' }
    }
    foreach ($time in @($Config.morningTime, $Config.monitorStart, $Config.monitorEnd)) {
        if ($time -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') { throw 'Use HH:mm clock times.' }
    }
    if ($Config.monitorStart -ge $Config.monitorEnd) { throw 'Monitoring must end after it starts, within the same day.' }
    foreach ($window in @($Config.taskWindows) + @($Config.breaks)) {
        Assert-RequiredField $window @('start', 'end')
        if ($window.start -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$' -or
            $window.end -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$' -or $window.start -ge $window.end) {
            throw 'Task windows and breaks must be valid same-day HH:mm intervals.'
        }
    }
    if (@($Config.taskWindows).Count -eq 0) { throw 'At least one task window is required.' }
    [void][TimeZoneInfo]::FindSystemTimeZoneById($Config.windowsTimezone)
    if ($Config.timezone -notmatch '^[A-Za-z_]+/[A-Za-z_+\-/0-9]+$' -and $Config.timezone -ne 'UTC') { throw 'Supply an IANA timezone.' }
    [void][DateTimeOffset]::Parse($Config.screenshotSince)
    foreach ($path in @($Config.todoPaths) + @($Config.screenshotFolders)) {
        if (-not [IO.Path]::IsPathRooted($path)) { throw 'Input paths must be absolute.' }
    }
    foreach ($path in $Config.todoPaths) {
        if ([IO.Path]::GetExtension($path) -ne '.md') { throw 'To-do inputs must be Markdown files.' }
    }
}

function Get-AssistantState {
    param([string]$Workspace)
    $snapshots = @(Get-ChildItem -LiteralPath (Join-Path $Workspace 'journal') -Filter '*.json' -File |
            Sort-Object Name -Descending)
    if ($snapshots.Count -eq 0) { throw 'Workspace is not initialized.' }
    # Never fall back to an older snapshot silently: it could resurrect completed work.
    $state = [IO.File]::ReadAllText($snapshots[0].FullName) | ConvertFrom-Json
    if ($state.schemaVersion -ne 1) { throw 'Unsupported state version. Upgrade before writing.' }
    return $state
}

function Write-Projection {
    param([string]$Workspace, $State)
    Write-AtomicText (Join-Path $Workspace 'context.md') $State.context
    Write-AtomicText (Join-Path $Workspace 'config.json') ($State.config | ConvertTo-Json -Depth 30)
    Write-AtomicText (Join-Path $Workspace 'state.json') ($State | ConvertTo-Json -Depth 100)
    $inferred = @('# Screenshot-derived actions', '', 'Generated from committed observations. Correct these through Assistant update.', '')
    foreach ($shot in $State.screenshots) {
        $inferred += "## $($shot.hash)"
        $inferred += "Source: $($shot.path)"
        $inferred += "Outcome: $($shot.outcome)"
        $inferred += "Observed: $($shot.observation)"
        $inferred += "Visible dates: $($shot.visibleDates -join ', ')"
        foreach ($task in @($State.tasks | Where-Object { $_.screenshotHash -eq $shot.hash })) {
            $inferred += "- [$($task.status)] $($task.id): $($task.title)"
            $inferred += "  Confidence: $($task.confidence); interpretation: $($task.interpretation)"
        }
        $inferred += ''
    }
    Write-AtomicText (Join-Path $Workspace 'inferred-actions.md') ($inferred -join "`n")
    $register = @('# Task register', '')
    foreach ($task in $State.tasks) {
        $register += "## $($task.id): $($task.title)"
        $register += "Status: $($task.status); parent: $($task.parentId)"
        $register += "Source: $($task.source)"
        $register += "Priority: $($task.priority); deadline: $($task.deadline)"
        $register += "Next step: $($task.nextStep)"
        $register += ''
    }
    Write-AtomicText (Join-Path $Workspace 'tasks.md') ($register -join "`n")
    $questions = @('# Questions', '')
    foreach ($question in $State.questions) {
        $questions += "- $($question.id) [$($question.status)]: $($question.text)"
        $questions += "  Answer: $($question.answer); revisit: $($question.revisitAfter)"
    }
    Write-AtomicText (Join-Path $Workspace 'questions.md') ($questions -join "`n")
    if ($null -ne $State.plan) {
        Write-AtomicText (Join-Path $Workspace 'today.md') $State.plan.markdown
        $planName = '{0}-r{1:D8}.md' -f $State.plan.date, [int]$State.revision
        $planPath = Join-Path (Join-Path $Workspace 'plans') $planName
        if (-not [IO.File]::Exists($planPath)) { Write-AtomicText $planPath $State.plan.markdown }
    }
    Write-AtomicText (Join-Path $Workspace 'projection-revision.txt') ([string]$State.revision)
}

function Save-AssistantState {
    param([string]$Workspace, $State, [string]$Reason)
    $State.revision = [int]$State.revision + 1
    $State.updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $State.lastChange = $Reason
    $path = Join-Path (Join-Path $Workspace 'journal') ('{0:D8}.json' -f $State.revision)
    if (Test-Path -LiteralPath $path) { throw 'Revision already exists.' }
    # One immutable snapshot is the transaction commit. Projections can be rebuilt after a crash.
    Write-AtomicText $path ($State | ConvertTo-Json -Depth 100)
    Write-Projection $Workspace $State
}

function Assert-Run {
    param($State, [string]$RunToken)
    if ($null -eq $State.activeRun -or $State.activeRun.token -cne $RunToken) { throw 'Run ownership lost or not acquired.' }
    if ([DateTimeOffset]::Parse($State.activeRun.expiresAt) -lt [DateTimeOffset]::UtcNow) {
        throw 'Run lease expired. Explicit recovery is required; do not call connectors.'
    }
}

function Get-ScreenshotCandidate {
    param($State)
    $seen = @{}
    foreach ($shot in $State.screenshots) { $seen[$shot.hash] = $true }
    $results = @()
    foreach ($folder in $State.config.screenshotFolders) {
        try {
            $files = @(Get-ChildItem -LiteralPath $folder -File -ErrorAction Stop | Where-Object {
                    $_.Extension.ToLowerInvariant() -in '.png', '.jpg', '.jpeg', '.webp', '.heic'
                })
        }
        catch { $results += [pscustomobject]@{ path = $folder; status = 'unavailable'; error = $_.Exception.Message }; continue }
        foreach ($file in $files) {
            if ($file.LastWriteTimeUtc -lt [DateTimeOffset]::Parse($State.config.screenshotSince).UtcDateTime) { continue }
            if ($file.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddSeconds(-30) -or $file.Length -eq 0) { continue }
            try {
                $stream = [IO.File]::Open($file.FullName, 'Open', 'Read', 'Read')
                $algorithm = [Security.Cryptography.SHA256]::Create()
                try { $hash = ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
                finally { $stream.Dispose(); $algorithm.Dispose() }
                $fresh = Get-Item -LiteralPath $file.FullName
                if ($fresh.Length -ne $file.Length -or $fresh.LastWriteTimeUtc -ne $file.LastWriteTimeUtc) { continue }
                if (-not $seen.ContainsKey($hash)) {
                    $seen[$hash] = $true
                    $results += [pscustomobject]@{ path = $file.FullName; hash = $hash; status = 'new'; bytes = $file.Length }
                }
            }
            catch { $results += [pscustomobject]@{ path = $file.FullName; status = 'unavailable'; error = $_.Exception.Message } }
        }
    }
    return $results
}

function Assert-Draft {
    param($Draft, $State)
    Assert-RequiredField $Draft @('baseRevision', 'context', 'tasks', 'screenshots', 'questions', 'plan', 'reason')
    if ($Draft.baseRevision -ne $State.revision) { throw 'Stale draft. Read latest state and rebase.' }
    $ids = @{}
    foreach ($task in $Draft.tasks) {
        Assert-RequiredField $task @('id', 'title', 'status', 'source', 'screenshotHash', 'confidence', 'interpretation',
            'parentId', 'priority', 'deadline', 'nextStep')
        if ($task.id -notmatch '^t-[a-zA-Z0-9-]+$' -or $ids.ContainsKey($task.id)) { throw 'Invalid or duplicate task ID.' }
        $ids[$task.id] = $true
        if ($task.status -notin 'open', 'in_progress', 'blocked', 'needs_context', 'done', 'dismissed', 'missing') { throw 'Invalid task status.' }
        if ($task.confidence -notin 'explicit', 'high', 'medium', 'low') { throw 'Invalid confidence.' }
    }
    foreach ($old in $State.tasks) {
        if (-not $ids.ContainsKey($old.id)) { throw 'Do not delete task history; mark status instead.' }
    }
    $hashes = @{}
    $candidates = @(Get-ScreenshotCandidate $State)
    foreach ($shot in $Draft.screenshots) {
        Assert-RequiredField $shot @('hash', 'path', 'observation', 'visibleDates', 'outcome')
        if ($shot.hash -notmatch '^[0-9a-f]{64}$' -or $hashes.ContainsKey($shot.hash)) { throw 'Invalid or duplicate screenshot hash.' }
        if ($shot.outcome -notin 'actions', 'no_action', 'needs_context') { throw 'Invalid screenshot outcome.' }
        $hashes[$shot.hash] = $true
        $old = @($State.screenshots | Where-Object { $_.hash -eq $shot.hash })
        if ($old.Count -and ($old[0] | ConvertTo-Json -Depth 20 -Compress) -cne ($shot | ConvertTo-Json -Depth 20 -Compress)) {
            throw 'Screenshot observations are immutable; change task interpretation instead.'
        }
        if (-not $old.Count) {
            $actual = @($candidates | Where-Object { $_.status -eq 'new' -and $_.hash -eq $shot.hash -and $_.path -eq $shot.path })
            if ($actual.Count -ne 1) { throw 'New screenshot must match a current stable source file.' }
        }
    }
    foreach ($old in $State.screenshots) {
        if (-not $hashes.ContainsKey($old.hash)) { throw 'Do not remove screenshot history.' }
    }
    foreach ($task in $Draft.tasks) {
        if ($task.screenshotHash -and -not $hashes.ContainsKey($task.screenshotHash)) { throw 'Task references an unknown screenshot.' }
        if ($task.parentId -and -not $ids.ContainsKey($task.parentId)) { throw 'Task references an unknown parent.' }
    }
    $questionIds = @{}
    foreach ($question in $Draft.questions) {
        Assert-RequiredField $question @('id', 'text', 'taskId', 'status', 'answer', 'lastAskedAt', 'revisitAfter')
        if ($questionIds.ContainsKey($question.id)) { throw 'Duplicate question ID.' }
        $questionIds[$question.id] = $true
        if ($question.status -notin 'open', 'answered', 'deferred', 'dismissed') { throw 'Invalid question status.' }
    }
    foreach ($old in $State.questions) {
        if (-not $questionIds.ContainsKey($old.id)) { throw 'Preserve question history.' }
    }
    if ($null -eq $Draft.plan) { return }
    Assert-RequiredField $Draft.plan @('date', 'actions', 'availableMinutes', 'questions', 'markdown', 'calendarFresh')
    if ($Draft.plan.date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'Invalid plan date.' }
    if ($Draft.plan.availableMinutes -lt 0) { throw 'Capacity cannot be negative.' }
    foreach ($questionId in $Draft.plan.questions) {
        if (-not $questionIds.ContainsKey($questionId)) { throw 'Plan refers to an unknown question.' }
    }
    if (@($Draft.plan.actions).Count -gt $State.config.maxActions -or @($Draft.plan.questions).Count -gt 2) { throw 'Plan exceeds action/question cap.' }
    $minutes = 0
    $selected = @{}
    foreach ($action in $Draft.plan.actions) {
        Assert-RequiredField $action @('taskId', 'action', 'doneWhen', 'minutes', 'startHere')
        if (-not $ids.ContainsKey($action.taskId) -or $selected.ContainsKey($action.taskId)) { throw 'Unknown or repeated planned task.' }
        $selected[$action.taskId] = $true
        $task = @($Draft.tasks | Where-Object { $_.id -eq $action.taskId })[0]
        if ($task.status -notin 'open', 'in_progress') { throw 'Only actionable tasks can be planned.' }
        if ($action.minutes -lt 1 -or $action.minutes -gt 60 -or -not $action.action -or -not $action.doneWhen) { throw 'Invalid action or completion condition.' }
        $minutes += $action.minutes
    }
    if ($minutes -gt [math]::Floor($Draft.plan.availableMinutes * $State.config.capacityFraction)) { throw 'Plan exceeds available capacity.' }
    $first = @($Draft.plan.actions | Where-Object { $_.startHere -eq $true })
    if (@($Draft.plan.actions).Count -gt 0 -and $first.Count -ne 1) { throw 'Select exactly one Start here action.' }
}

function Invoke-AssistantCommand {
    [CmdletBinding()]
    param([string]$Workspace, [string]$Command, $Request, [string]$RunToken)
    $Workspace = [IO.Path]::GetFullPath($Workspace)
    $pluginRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
    $repositoryRoot = Split-Path $pluginRoot -Parent
    $protectedRoot = $pluginRoot
    if ((Test-Path -LiteralPath (Join-Path $repositoryRoot '.git')) -or
        (Test-Path -LiteralPath (Join-Path $repositoryRoot 'tools/Install.ps1'))) { $protectedRoot = $repositoryRoot }
    if ($Workspace.TrimEnd('\') -eq $protectedRoot -or $Workspace.StartsWith($protectedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Private workspace must be outside the plugin and source repository.'
    }
    if (-not [IO.Directory]::Exists($Workspace)) {
        if ($Command -ne 'Init') { throw 'Workspace does not exist.' }
        [void][IO.Directory]::CreateDirectory($Workspace)
    }
    $lockPath = Join-Path $Workspace '.command.lock'
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Workspace busy. Another command is committing; retry later.' }
    try {
        if ($Command -eq 'Init') {
            Assert-Config $Request.config
            $journal = Join-Path $Workspace 'journal'
            if (@(Get-ChildItem -LiteralPath $journal -Filter '*.json' -ErrorAction SilentlyContinue).Count) { return Get-AssistantState $Workspace }
            [void][IO.Directory]::CreateDirectory($journal)
            [void][IO.Directory]::CreateDirectory((Join-Path $Workspace 'plans'))
            $state = [pscustomobject]@{
                schemaVersion = 1; revision = 0; installationId = [guid]::NewGuid().ToString('N')
                updatedAt = ''; lastChange = ''; config = $Request.config; context = $Request.context
                activeRun = $null; tasks = @(); screenshots = @(); questions = @(); plan = $null
                calendarOperations = @(); blocks = @(); sourceOperations = @(); schedules = @()
            }
            Save-AssistantState $Workspace $state 'Initialized private workspace'
            return $state
        }
        $state = Get-AssistantState $Workspace
        switch ($Command) {
            'Read' { return $state }
            'Recover' {
                if ($Request.abandonRun) {
                    if (-not $Request.reason) { throw 'Explain why the previous run can no longer be active.' }
                    $state.activeRun = $null
                    Save-AssistantState $Workspace $state $Request.reason
                }
                else { Write-Projection $Workspace $state }
                return $state
            }
            'Begin' {
                if ($null -ne $state.activeRun) { throw 'Another run owns this workspace. Expired runs require explicit recovery.' }
                $contextPath = Join-Path $Workspace 'context.md'
                $projectionMarker = Join-Path $Workspace 'projection-revision.txt'
                if ((Test-Path -LiteralPath $contextPath) -and (Test-Path -LiteralPath $projectionMarker)) {
                    # Only adopt an edit to a fully rendered revision. A stale view after a crash
                    # must never roll back newer committed memory.
                    if ([IO.File]::ReadAllText($projectionMarker).Trim() -eq [string]$state.revision) {
                        $state.context = [IO.File]::ReadAllText($contextPath)
                    }
                }
                $state.activeRun = [pscustomobject]@{ token = [guid]::NewGuid().ToString('N'); expiresAt = [DateTimeOffset]::UtcNow.AddMinutes(120).ToString('o') }
                Save-AssistantState $Workspace $state 'Run started'
                return $state
            }
        }
        Assert-Run $state $RunToken
        switch ($Command) {
            'Renew' { $state.activeRun.expiresAt = [DateTimeOffset]::UtcNow.AddMinutes(120).ToString('o') }
            'End' { $state.activeRun = $null }
            'Discover' { return @(Get-ScreenshotCandidate $state) }
            'Commit' {
                Assert-Draft $Request $state
                foreach ($field in 'context', 'tasks', 'screenshots', 'questions', 'plan') { $state.$field = $Request.$field }
            }
            'Configure' {
                Assert-Config $Request.config
                if ($state.config.writeCalendarId -ne $Request.config.writeCalendarId -and @($state.blocks).Count) {
                    throw 'Resolve existing calendar blocks before switching writable calendars.'
                }
                $state.config = $Request.config
            }
            'Schedules' {
                if (@($Request.schedules).Count -ne 2) { throw 'Exactly morning and monitor schedule records required.' }
                foreach ($schedule in $Request.schedules) {
                    Assert-RequiredField $schedule @('kind', 'id', 'host', 'deliver', 'prompt', 'status')
                    if ($schedule.host -ne 'hermes') { throw 'New schedules must use Hermes cron.' }
                }
                if (@($Request.schedules.kind | Sort-Object -Unique).Count -ne 2 -or
                    'morning' -notin $Request.schedules.kind -or 'monitor' -notin $Request.schedules.kind) { throw 'Invalid schedule kinds.' }
                $state.schedules = $Request.schedules
            }
            'PrepareCalendar' { Add-CalendarOperation $state $Request }
            'DispatchCalendar' {
                $operationMatches = @($state.calendarOperations | Where-Object { $_.id -eq $Request.operationId })
                if ($operationMatches.Count -ne 1 -or $operationMatches[0].status -ne 'pending') { throw 'Only a pending operation can dispatch once.' }
                $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($operationMatches[0].preparedAt)
                if ($age.TotalSeconds -gt 120 -or $age.TotalSeconds -lt -5) { throw 'Prepared operation expired; reconcile and refresh.' }
                $operation = $operationMatches[0]
                if ($operation.action -eq 'create') { $startTime = $operation.connectorArguments.start_time }
                else { $startTime = $operation.before.start }
                if ([DateTimeOffset]::Parse($startTime) -le [DateTimeOffset]::UtcNow) { throw 'Block has started; reconcile without dispatch.' }
                if ($operation.action -eq 'update' -and [DateTimeOffset]::Parse($operation.connectorArguments.start_time) -le [DateTimeOffset]::UtcNow) {
                    throw 'New block start has passed; reconcile without dispatch.'
                }
                $operation.status = 'uncertain'
                $operation.result = 'Dispatch claimed before network mutation; reconcile before any retry.'
            }
            'CompleteCalendar' { Complete-CalendarOperation $state $Request }
            'Override' {
                $block = @($state.blocks | Where-Object { $_.taskId -eq $Request.taskId -and $_.date -eq $Request.date })
                if ($block.Count -ne 1) { throw 'Unknown calendar block.' }
                $block[0].status = 'user_override'
            }
            'CompleteSource' { Complete-SourceCheckbox $Workspace $state $Request }
            'ReconcileSource' { Resolve-SourceOperation $state $Request }
            default { throw "Unknown command: $Command" }
        }
        $reason = $Command
        if ($null -ne $Request -and 'reason' -in $Request.PSObject.Properties.Name) { $reason = $Request.reason }
        Save-AssistantState $Workspace $state $reason
        return $state
    }
    finally { $lock.Dispose() }
}

# Calendar and external-file mutations have separate protocols from general task commits.
. (Join-Path $PSScriptRoot 'Calendar.ps1')
. (Join-Path $PSScriptRoot 'Source.ps1')
Export-ModuleMember -Function Invoke-AssistantCommand
