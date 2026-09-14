---
name: assistant-update
description: Record progress, answer screenshot or task questions, correct context, or change today's capacity for an installed Personal Assistant, then adjust its plan.
---

# Assistant update

Read [runtime](../../references/runtime.md). Read [calendar](../../references/calendar.md)
only when a calendar change is needed. Acquire a run lease and read the private
workspace's current context, tasks, questions, and plan before interpreting a reply.
If the conversation does not identify an installation, ask for its workspace.

Resolve phrases like "the first action" against the latest plan actually shown to
the user, not a newer silent draft. If that mapping or a named task is ambiguous,
ask one precise question and keep the remaining changes. Never infer completion
from elapsed time or an absent source.

- **Progress:** Reuse the task ID. Record done/in_progress/blocked as explicitly
  reported, keeping the parent goal open until it is actually complete.
- **Context:** Update confirmed facts and preferences in context, supersede the
  old statement, and explain the correction in the commit reason. Keep labeled
  hypotheses separate. A temporary "30 minutes today" override gets today's date
  and expires after today; it is not a permanent preference.
- **Screenshot answers:** Update the existing task interpretation and resolve the
  linked question. Preserve original screenshot evidence/hash. "Just inspiration"
  can dismiss the candidate, not delete its history.
- **Priority changes:** Update the relevant goal/task and re-evaluate today's
  remaining actions. Distinguish explicit priority from the previous estimate.
- **Deferral:** Set revisitAfter, status deferred, and avoid asking before then.

Commit updates before synchronizing external sources. For an explicitly completed
task with an exact unchecked source checkbox, read the complete source and its
SHA-256, then call CompleteSource with that exact line number/text and the actual
user report. The helper preserves UTF-8 encoding, BOM, and line endings. Ambiguous
matches, free-form entries, changed files, and non-UTF-8 files stay recorded in the
assistant register; ask for a mapping instead of rewriting the original list.

For a pending source operation after interruption, compare actual source bytes
against its beforeHash and afterHash. afterHash proves completion; beforeHash means
the source was unchanged. If neither matches, preserve the user's file and inspect
the exact checkbox afresh. Never restore a backup over a newer user edit. Record the
reconciliation with ReconcileSource; new CompleteSource attempts must remap
from the current file, and no attempt is needed if it is already checked.

End this lease before invoking Assistant run for material replanning; don't nest
run leases. Invoke run in manual mode so fresh calendar data and remaining capacity
are used. If a clarification requires no plan change, reply briefly and don't churn
the calendar. Ask at most two consequential questions and continue unrelated work.
