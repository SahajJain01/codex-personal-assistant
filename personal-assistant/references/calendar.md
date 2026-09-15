# Hermes Google Calendar protocol

Load the installed google-workspace skill. Follow its authentication instructions
for Calendar access using the current Hermes profile. Do not implement OAuth, copy
Codex tokens, or save credentials in this workspace. Use the Python environment
reported by `hermes --version`, with its Google API client dependencies. Locate
`google-workspace/scripts/google_api.py` through skill_view. The bridge imports
its `build_service` function; setup must verify this capability on the target version.

Use absolute paths and shell argument arrays. Replace these placeholders:

```text
<Hermes Python> <skill>/scripts/calendar_bridge.py --google-script <Google skill>/scripts/google_api.py calendars
<Hermes Python> <skill>/scripts/calendar_bridge.py --google-script <Google skill>/scripts/google_api.py events --calendar <ID> --start <RFC3339> --end <RFC3339> --timezone <IANA>
<Hermes Python> <skill>/scripts/calendar_bridge.py --google-script <Google skill>/scripts/google_api.py get --calendar <ID> --event <ID>
```

`calendars` and `events` finish pagination or fail without returning partial data.
Events remain full Google resources: retain cancellations, recurring-instance and
all-day semantics when reasoning. `get` returns raw and normalized representations.
Do not use the built-in skill's simplified list output for ownership or completeness.

## Read and normalize

Search events with explicit RFC3339 bounds and IANA timezone on all configured
calendars. Follow nextPageToken until absent. Never use a keyword query to infer
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

Use the bridge get output as the canonical normalization. It also includes a
details object tracking location, color, attachments, custom properties and guest
permissions; preserve it unchanged. The JSON above shows the baseline fields.

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

3. Read the returned state. Only dispatch a newly prepared pending operation:

```text
<Hermes Python> <skill>/scripts/calendar_bridge.py --google-script <Google skill>/scripts/google_api.py dispatch --workspace <absolute path> --run-token <token> --operation <prepared ID>
```

   The bridge translates the saved legacy-named connectorArguments to Google API
   fields, refreshes overlap events, checks the full original owned event, claims
   DispatchCalendar, then sends once. Update/delete use If-Match ETags. It reads
   back and calls CompleteCalendar on success. It never retries mutations.
   Do not bypass this bridge with generic Google create/update/delete commands.
   A failure after dispatch leaves an uncertain operation for reconciliation.
   Preview never prepares or dispatches writes.

4. For recovery only, read back the changed event or verify deletion, then call CompleteCalendar:

```json
{"operationId":"returned-id","outcome":"applied","event":null,"evidence":"Actual tool result/readback summary"}
```

event is the normalized full event for create/update, null for deletion. The helper
verifies the planned fields and saves the returned event ID/fingerprint. Use
outcome uncertain if the call times out or readback is unavailable. not_applied
requires definite rejection or authoritative reconciliation, not a network error.

## Recover uncertain results

Never blindly repeat create. For bridge-created operations, first get the deterministic
event ID `pa` followed by the operation ID (32 hex characters). Legacy Codex
operations may have different IDs; reconcile those by marker before migration. Search the write calendar over the intended interval
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
Conditional ETags protect update/delete from concurrent edits to that event.
Calendar availability across events/calendars is not transactional: another event
can still be added after the overlap check. Report conflicts and replan rather than
claiming atomic calendar reservations. A 412 response is not permission to overwrite;
preserve the user's change and reconcile. Never classify auth failures as deletion.
