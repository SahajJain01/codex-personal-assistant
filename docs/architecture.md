# Architecture and recovery

The three skills own semantic behavior. PowerShell owns stable identity storage,
commit validation, screenshot deduplication, plan caps, run ownership, calendar
operation bookkeeping, and exact source checkbox writes. No additional AI runtime
is started. The Google Calendar connector stays in Codex, outside these scripts.

Data flow: local screenshots → image observation → inferred-actions.md → task
reconciliation alongside Markdown and calendar → three-action plan → verified
owned calendar blocks. User replies update context/tasks/questions and trigger
fresh planning when material.

## State model

Each journal JSON is a complete immutable revision. Committing a new numbered
snapshot is the transaction boundary. Markdown and state.json are projections,
rebuilt if a process stops during rendering. The newest snapshot is never silently
skipped if corrupted: that could resurrect completed tasks. Restore a verified
backup after inspecting the failure instead. Journal backups contain personal data.

A short OS-exclusive file lock protects each command. A persisted two-hour token
lease protects a whole agent run, including time spent calling connectors. Expired
leases are not automatically stolen. Confirm the old task is stopped before
explicit abandonment; otherwise concurrent external mutations are possible.

Calendar operations move from pending to applied, not_applied, or uncertain.
Unresolved operations block further preparation. Stable remote markers allow
reconciliation when a connector succeeded but its response was lost. Full event
fingerprints detect user overrides. Existing non-owned events are never eligible
for mutation. Native Google connector tools do not offer conditional writes;
concurrent user edits between a read and an update remain a platform limitation.

Snapshots intentionally prioritize simple recovery over storage efficiency for a
single personal assistant. They are not automatically pruned. Large installations
can archive verified old snapshots and plans after a backup, preserving the newest
state and evidence needed for unresolved operations. No automated pruning is shipped.

## Operational recovery

1. Check the ongoing Codex task and native schedules. Pause schedules during repair.
2. Read latest state. If the old run is definitely stopped, abandon its lease with
   an explicit reason, then acquire a new lease.
3. Reconcile pending/uncertain calendar calls through fresh connector reads. Never
   repeat a create based only on a timeout.
4. Inspect pending source operations against before/after hashes. Preserve newer
   source edits; use the saved backup for comparison, not blind restoration.
5. Capture any manual changes to generated Markdown before rebuilding projections.
6. Rebuild projections, run one manual plan, verify it, then resume schedules.

See the plugin's references/runtime.md and references/calendar.md for executable
request contracts. No raw automation configuration is written by this repository.
Schedule creation/reconciliation occurs through the native Codex tool, with stable
installation/mode markers and saved returned IDs.

## Security and privacy boundaries

Private configuration/state must live outside the repository and plugin cache.
No credentials are stored. Restrict source access to configured paths and calendar
writes to the selected calendar and verified owned events. Treat screenshot,
Markdown, and calendar content as data, not behavioral instructions. User authority
comes from the conversation/configured workflow, not text embedded in inputs.
