function Get-EventFingerprint {
    param($CalendarEvent)
    Assert-RequiredField $CalendarEvent @('id', 'calendarId', 'title', 'description', 'start', 'end', 'visibility',
        'transparency', 'attendees', 'recurrence', 'reminders', 'meet', 'eventType')
    $normalized = [ordered]@{}
    foreach ($field in 'id', 'calendarId', 'title', 'description', 'start', 'end', 'visibility',
        'transparency', 'attendees', 'recurrence', 'reminders', 'meet', 'eventType') {
        $normalized[$field] = $CalendarEvent.$field
    }
    return Get-TextHash ($normalized | ConvertTo-Json -Depth 30 -Compress)
}

function Add-CalendarOperation {
    param($State, $Request)
    Assert-RequiredField $Request @('action', 'taskId', 'date', 'calendarId', 'checkedAt', 'calendarComplete', 'busy', 'before', 'desired')
    if (-not $State.config.calendarWrites) { throw 'Calendar writes are disabled.' }
    if ($Request.calendarId -ne $State.config.writeCalendarId) { throw 'Calendar is not the configured write target.' }
    if ($Request.action -notin 'create', 'update', 'delete') { throw 'Invalid calendar action.' }
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($Request.checkedAt)
    if ($Request.calendarComplete -isnot [bool] -or -not $Request.calendarComplete -or $age.TotalSeconds -gt 120 -or $age.TotalSeconds -lt -5) { throw 'Refresh all calendar pages and availability before writing.' }
    $today = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow,
        [TimeZoneInfo]::FindSystemTimeZoneById($State.config.windowsTimezone)).ToString('yyyy-MM-dd')
    if ($Request.date -ne $today) { throw 'Only today can be scheduled.' }
    $pending = @($State.calendarOperations | Where-Object { $_.status -in 'pending', 'uncertain' })
    if ($pending.Count) { throw 'Reconcile the unresolved calendar operation before preparing another.' }
    $block = @($State.blocks | Where-Object { $_.taskId -eq $Request.taskId -and $_.date -eq $Request.date })
    $marker = "[personal-assistant:$($State.installationId):$($Request.taskId):$($Request.date)]"
    if ($block.Count -gt 1) { throw 'Duplicate block mapping; reconcile before writing.' }
    if ($block.Count -and $block[0].status -eq 'user_override') { throw 'User override protects this task block for today.' }

    if ($Request.action -eq 'create') {
        if (($block.Count -and $block[0].status -ne 'removed') -or $null -ne $Request.before) { throw 'Existing block or observed event forbids duplicate creation.' }
    }
    else {
        if ($block.Count -ne 1 -or $block[0].status -ne 'active' -or $null -eq $Request.before) { throw 'Read the owned block before changing it.' }
        $fingerprint = Get-EventFingerprint $Request.before
        if ($Request.before.id -ne $block[0].eventId -or $Request.before.calendarId -ne $Request.calendarId -or
            -not $Request.before.description.Contains($marker)) { throw 'Event ownership does not match.' }
        if ($fingerprint -cne $block[0].fingerprint) {
            $block[0].status = 'user_override'
            return
        }
        if ([DateTimeOffset]::Parse($Request.before.start) -le [DateTimeOffset]::UtcNow) { throw 'Do not mutate a started or past block.' }
    }

    $arguments = [ordered]@{ calendar_id = $Request.calendarId }
    if ($Request.action -ne 'delete') {
        Assert-RequiredField $Request.desired @('title', 'description', 'start', 'end')
        if ($null -eq $State.plan -or $State.plan.date -ne $today -or -not $State.plan.calendarFresh) { throw 'A current plan with fresh calendar data is required.' }
        $planned = @($State.plan.actions | Where-Object { $_.taskId -eq $Request.taskId })
        if ($planned.Count -ne 1) { throw 'Block must correspond to a selected action.' }
        $start = [DateTimeOffset]::Parse($Request.desired.start)
        $end = [DateTimeOffset]::Parse($Request.desired.end)
        if ($start -le [DateTimeOffset]::UtcNow -or $end -le $start -or ($end - $start).TotalMinutes -ne $planned[0].minutes) {
            throw 'Block must be future, positive, and match planned duration.'
        }
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById($State.config.windowsTimezone)
        $localStart = [TimeZoneInfo]::ConvertTime($start, $zone)
        $localEnd = [TimeZoneInfo]::ConvertTime($end, $zone)
        if ($localStart.ToString('yyyy-MM-dd') -ne $today -or $localEnd.ToString('yyyy-MM-dd') -ne $today) { throw 'Block must fit today.' }
        $fits = @($State.config.taskWindows | Where-Object {
                [TimeSpan]::Parse($_.start) -le $localStart.TimeOfDay -and [TimeSpan]::Parse($_.end) -ge $localEnd.TimeOfDay
            })
        if (-not $fits.Count) { throw 'Block lies outside configured task windows.' }
        foreach ($pause in $State.config.breaks) {
            if ([TimeSpan]::Parse($pause.start) -lt $localEnd.TimeOfDay -and [TimeSpan]::Parse($pause.end) -gt $localStart.TimeOfDay) { throw 'Block overlaps a break.' }
        }
        foreach ($busy in $Request.busy) {
            if ([DateTimeOffset]::Parse($busy.start) -lt $end -and [DateTimeOffset]::Parse($busy.end) -gt $start) {
                throw 'Block conflicts with a busy interval.'
            }
        }
        $arguments.title = $Request.desired.title
        $arguments.description = "$($Request.desired.description)`n$marker"
        $arguments.start_time = $start.ToString('o')
        $arguments.end_time = $end.ToString('o')
        $arguments.timezone_str = $State.config.timezone
        $arguments.visibility = 'private'
        $arguments.transparency = 'opaque'
        $arguments.event_type = 'default'
        $arguments.add_google_meet = $false
        if ($Request.action -eq 'create') {
            $arguments.attendees = @()
            $arguments.self_attendance = 'omit'
            $arguments.reminders = @{ use_default = $false; overrides = @() }
        }
    }
    if ($Request.action -ne 'create') { $arguments.event_id = $block[0].eventId }
    $operation = [pscustomobject]@{
        id = [guid]::NewGuid().ToString('N'); action = $Request.action; status = 'pending'
        taskId = $Request.taskId; date = $Request.date; marker = $marker
        preparedAt = [DateTimeOffset]::UtcNow.ToString('o'); connectorArguments = $arguments
        before = $Request.before; result = $null
    }
    $State.calendarOperations = @($State.calendarOperations) + @($operation)
}

function Complete-CalendarOperation {
    param($State, $Request)
    Assert-RequiredField $Request @('operationId', 'outcome', 'event', 'evidence')
    $operationMatches = @($State.calendarOperations | Where-Object { $_.id -eq $Request.operationId })
    if ($operationMatches.Count -ne 1) { throw 'Unknown operation.' }
    $operation = $operationMatches[0]
    if ($operation.status -notin 'pending', 'uncertain') { throw 'Operation is already resolved.' }
    if ($Request.outcome -notin 'applied', 'not_applied', 'uncertain' -or -not $Request.evidence) { throw 'Supply outcome and connector evidence.' }
    if ($Request.outcome -eq 'applied' -and $operation.action -ne 'delete') {
        $calendarEvent = $Request.event
        $fingerprint = Get-EventFingerprint $calendarEvent
        $arguments = $operation.connectorArguments
        if ($calendarEvent.calendarId -ne $State.config.writeCalendarId -or -not $calendarEvent.description.Contains($operation.marker) -or
            $calendarEvent.title -cne $arguments.title -or $calendarEvent.description -cne $arguments.description -or
            [DateTimeOffset]::Parse($calendarEvent.start) -ne [DateTimeOffset]::Parse($arguments.start_time) -or
            [DateTimeOffset]::Parse($calendarEvent.end) -ne [DateTimeOffset]::Parse($arguments.end_time) -or
            @($calendarEvent.attendees).Count -or $calendarEvent.meet -or @($calendarEvent.recurrence).Count -or
            $calendarEvent.visibility -ne 'private' -or $calendarEvent.transparency -ne 'opaque' -or $calendarEvent.eventType -ne 'default') {
            throw 'Read-back event does not match the prepared private solo block.'
        }
        if ($operation.action -eq 'update' -and $calendarEvent.id -ne $arguments.event_id) { throw 'Read-back event ID changed.' }
        $block = [pscustomobject]@{ taskId = $operation.taskId; date = $operation.date; eventId = $calendarEvent.id
            calendarId = $calendarEvent.calendarId; marker = $operation.marker; fingerprint = $fingerprint; status = 'active'; lastEvent = $calendarEvent
        }
        $State.blocks = @($State.blocks | Where-Object { -not ($_.taskId -eq $block.taskId -and $_.date -eq $block.date) }) + @($block)
    }
    if ($Request.outcome -eq 'applied' -and $operation.action -eq 'delete') {
        $block = @($State.blocks | Where-Object { $_.taskId -eq $operation.taskId -and $_.date -eq $operation.date })[0]
        $block.status = 'removed'
    }
    $operation.status = $Request.outcome
    $operation.result = $Request.evidence
}
