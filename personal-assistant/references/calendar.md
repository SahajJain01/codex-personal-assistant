# Calendar connector protocol

Use the installed Google Calendar connector, discovered on the target host.
Do not implement direct OAuth, store tokens, or use browser automation as a silent
fallback. Read actual tool schemas: tool names and supported fields can vary.
The helper produces arguments matching the currently verified connector contract;
if the host schema differs, stop calendar writes and report the mismatch.

## Read and normalize

Search events with explicit RFC3339 bounds and IANA timezone on all configured
calendars. Follow next_page_token until absent. Never use a keyword query to infer
an empty schedule. Read complete event details for owned blocks and uncertain
recurring/all-day entries. Busy/free lookup complements event reads; it cannot
replace titles, recurrence details, or ownership evidence. Treat per-calendar
permission errors as incomplete data.

Normalize an owned event to the following consistent object after a full read:

```json
{
  "id":"returned-event-id", "calendarId":"selected-calendar-id",
  "title":"Task title", "description":"Text including ownership marker",
  "start":"2026-09-14T09:00:00+07:00", "end":"2026-09-14T09:30:00+07:00",
  "visibility":"private", "transparency":"opaque", "attendees":[],
  "recurrence":[], "reminders":{"use_default":false,"overrides":[]},
  "meet":"", "eventType":"default"
}
```

Use empty arrays/strings for absence and preserve actual reminder fields/order
consistently. Attendees must reflect the actual complete event, not merely invited
guests after filtering out self. Exclude server timestamps from this fingerprint;
include all listed user-editable fields. If complete details are unavailable, do
not make an ownership-sensitive mutation.

Compare known blocks against stored lastEvent/fingerprint on every refresh. Missing
blocks require a direct read: only an explicit not-found or authoritative absence
establishes deletion; authorization failures are not deletion. Mark a confirmed
user edit/deletion with Override (`{"taskId":"t-id","date":"YYYY-MM-DD"}`)
and preserve it as a fixed commitment or deliberate removal. The helper detects
edits on update/delete and records user_override instead of preparing a write.
Don't create another block to circumvent an override. Overrides apply to that
task/day; the user can explicitly request a new plan for a future day.

## Prepare, call, verify, complete

1. Reconcile any pending/uncertain operations first. Renew the lease. Fetch fresh
   relevant events/availability, complete pagination, and recalculate conflicts.
2. Submit PrepareCalendar with this shape:

```json
{
  "action":"create", "taskId":"t-id", "date":"2026-09-14",
  "calendarId":"selected-calendar-id", "checkedAt":"actual current UTC timestamp",
  "calendarComplete":true, "busy":[{"start":"RFC3339","end":"RFC3339"}],
  "before":null,
  "desired":{"title":"Concrete action","description":"Done when: visible result","start":"RFC3339","end":"RFC3339"}
}
```

The dates above are examples. Use actual current values. busy is the union of all
current external commitments plus other owned blocks. For update only, exclude
the exact unchanged block being moved; free/busy alone cannot safely subtract it
where another event overlaps. Use event details to preserve those overlaps.
For update/delete, before is the fully read normalized owned event. For delete,
desired is null. The helper checks freshness, scope, ownership, future time,
task windows, breaks, duration, and overlap. It cannot authenticate evidence;
the agent must supply only actual connector results, never fabricated availability.

3. Read the returned state. Call a connector only if a new pending operation was
   actually prepared. Use its connectorArguments exactly once with create_event,
   update_event, or delete_event. These force private ordinary solo events without
   invitations or Meet links. Never call a scheduling connector in preview mode.
   Execute promptly (within two minutes of checking); refresh/reconcile if delayed.
4. Read back the changed event, or verify deletion. Call CompleteCalendar:

```json
{"operationId":"returned-id","outcome":"applied","event":null,"evidence":"Actual tool result/readback summary"}
```

event is the normalized full event for create/update, null for deletion. The helper
verifies the planned fields and saves the returned event ID/fingerprint. Use
outcome uncertain if the call times out or readback is unavailable. not_applied
requires definite rejection or authoritative reconciliation, not a network error.

## Recover uncertain results

Never blindly repeat create. Search the write calendar over the intended interval
and, if needed, the rest of today for the exact saved marker
`[personal-assistant:installationId:taskId:date]`; finish all pages and read matches.
For updates/deletes, read the known event ID too. Exactly one matching event in the
desired state can resolve applied. Multiple matches or a user-modified result need
inspection; keep uncertain and ask a focused question. A confirmed absent event
can resolve a create not_applied or delete applied. A confirmed unchanged original
can resolve update not_applied only after the original call has definitively ended.
An ambiguous still-running call is never safe to retry.

The operation journal stores the marker before calling Google, so a crash after
creation but before saving the event ID can still be reconciled. General task
Commit cannot overwrite block mappings or operation outcomes. Keep existing
appointments untouched even if they conflict with a critical task.

If the calendar is stale/unavailable, save a provisional action plan with
calendarFresh=false and postpone all writes. Partial sync is reported explicitly.
The connector does not expose a cross-service transaction or conditional-write
ETag in these tools: rereading minimizes, but cannot eliminate, a simultaneous
edit between read and update. Re-read afterward and stop on conflict; never claim
absolute race-free Google Calendar writes.
