# Runtime contract

The helper is `scripts/Assistant.ps1` relative to the skill root. Use absolute paths
when calling it. Use JSON request files to avoid shell interpolation of user data.
All request files belong in the private workspace's `requests` directory (create
it if needed). Do not put personal requests inside the skill source/cache.

```powershell
& '<skill-root>\scripts\Assistant.ps1' -Workspace '<private-workspace>' -Command Read
& '<skill-root>\scripts\Assistant.ps1' -Workspace '<private-workspace>' -Command Begin
& '<skill-root>\scripts\Assistant.ps1' -Workspace '<private-workspace>' -Command Commit -RunToken '<returned-token>' -RequestPath '<private-request.json>'
& '<skill-root>\scripts\Assistant.ps1' -Workspace '<private-workspace>' -Command End -RunToken '<returned-token>'
```

These angle-bracket values describe inputs; replace them with actual returned/configured
values. Every successful command returns JSON. Mutating commands return the new state.
Use state.activeRun.token for all commands between Begin and End. Renew returns a
new revision as well as extending the lease. Read is nonmutating. Discover requires
the lease and returns candidate/error records without changing revision.

## Persistence and concurrency

`journal/00000001.json` and subsequent numbered snapshots are immutable canonical
transactions. `state.json`, `config.json`, `context.md`, `tasks.md`, `questions.md`,
`inferred-actions.md`, and `today.md` are materialized views. A saved snapshot commits
even if rendering is interrupted. Recover rebuilds views. Do not directly edit
views; use Assistant update. If the user did edit a view, capture and reconcile it
as an explicit update before regenerating. Never silently discard a discovered edit.

The per-command OS lock serializes disk mutations. A durable two-hour run lease
also serializes agent runs across connector calls. No automatic lease takeover:
Recover with `{"abandonRun":true,"reason":"...evidence old task stopped..."}` is
only for a verified stopped run. `{"abandonRun":false}` just rebuilds projections.
Check unresolved calendar operations on restart before doing any external write.

## Commands and request shapes

- **Init:** `{"config":{...all config example fields...},"context":"# Context\n..."}`.
  Idempotent; an existing workspace is returned unchanged. Configure applies
  intentional configuration changes under a lease.
- **Configure:** `{"config":{...complete configuration...}}`.
- **Commit:** full proposed context/tasks/screenshots/questions/plan, plus
  baseRevision from the latest Read and a human-readable reason. Do not send
  operations, blocks, schedules, activeRun, or installationId; these are maintained
  by dedicated commands. Preserve all prior tasks/screenshots and question history.
- **Schedules:** `{"schedules":[{"kind":"morning","id":"actual-id","host":"hermes","deliver":"local","prompt":"saved prompt","status":"ACTIVE"},{"kind":"monitor","id":"actual-id","host":"hermes","deliver":"local","prompt":"saved prompt","status":"ACTIVE"}]}`.
- **CompleteSource:** `{"path":"absolute configured path","expectedHash":"file SHA256 lowercase","lineNumber":3,"expectedLine":"- [ ] Exact task","taskId":"t-id","userReport":"actual explicit completion report"}`.
- **ReconcileSource:** `{"operationId":"pending-source-operation-id"}`. Reads current
  bytes and resolves applied/not_applied/user_changed without modifying the source.
- **PrepareCalendar / DispatchCalendar / CompleteCalendar / Override:** see calendar.md.
- **Read / Begin / Renew / End / Discover:** no request required.

### Draft example

```json
{
  "baseRevision": 2,
  "reason": "User confirmed that the saved image concerns their own renewal",
  "context": "# Context\n\n## Confirmed facts\n...\n\n## Assumptions\n...",
  "tasks": [{
    "id": "t-renewal", "title": "Renew membership", "status": "open",
    "source": "screenshot path or Markdown path + heading + original text",
    "screenshotHash": "", "confidence": "explicit", "interpretation": "User confirmed intent",
    "parentId": "", "priority": "Explicit: high", "deadline": "",
    "nextStep": "Locate the renewal form"
  }],
  "screenshots": [],
  "questions": [],
  "plan": {
    "date": "2026-09-14", "availableMinutes": 120, "calendarFresh": true,
    "actions": [{"taskId":"t-renewal","action":"Locate the renewal form","doneWhen":"Form link is saved","minutes":20,"startHere":true}],
    "questions": [], "markdown": "# Today\n\n**Start here:** Locate the renewal form (20 min)."
  }
}
```

Replace date, IDs, and content with current evidence. Each task also supports extra
descriptive fields (e.g. original source text, explicit versus inferred dates).
Do not turn those extra fields into another source of operational truth.

Task status: open, in_progress, blocked, needs_context, done, dismissed, missing.
Confidence: explicit, high, medium, low. All example task fields are required;
use empty strings when not applicable. IDs are stable `t-...` values. Parent IDs
refer to other stored tasks, not calendar events.

Each screenshot record requires hash, path, observation, visibleDates (array),
and outcome (actions/no_action/needs_context). Its record is immutable after commit;
interpretations live on tasks. Successful observations with no tasks are still
committed to prevent repeated extraction. A failed inspection is not a record.

Each question requires id, text, taskId, status (open/answered/deferred/dismissed),
answer, lastAskedAt, revisitAfter. Use empty strings for absent dates/answers.
Plan.questions holds question IDs actually shown. Only mark lastAskedAt when shown.
When no plan exists, plan may be null; do not clear an existing plan casually.

## Failure handling

A rejected/stale draft changes nothing: Read and rebase. A rendering error after
commit may have saved the snapshot: Read before retrying. Never duplicate a
successful task or observation just because the tool response was interrupted.
Images still syncing are skipped; unreadable paths return error records. Source
and connector outages are surfaced as freshness limitations, never interpreted as
zero tasks or an empty day. Private requests, snapshots and source backups may
contain personal information; keep them out of the repository and skill archive.

DispatchCalendar takes {"operationId":"prepared-id"}, requires a live lease and
a preparation younger than two minutes, and changes pending to uncertain before
the bridge sends. It can only be claimed once. Old schema-1 journals are preserved.
