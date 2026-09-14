# Native schedules

Use Codex's `automation_update` tool discovered on the target host. Use heartbeat
schedules attached to the ongoing assistant task, executing locally in the private
workspace. Keep the user-selected/default model. No Windows Task Scheduler, custom
daemon, shell sleep loop, raw automation TOML writes, or assumed file-event trigger.

Persist two schedule records, morning and monitor. Each saved prompt contains the
installation ID, the absolute private workspace path, the explicitly invoked
`$assistant-run` skill, its mode, and the notification behavior below. These markers
are stable identifiers for reconciling setup after interrupted tool calls.

Before creating anything, read existing schedule IDs from state. Inspect the host's
automation inventory (including `$CODEX_HOME/automations/*/automation.toml` when
needed) and view matching IDs through the native tool. Search by installation ID,
mode and workspace. Reuse matches and preserve unrelated schedules. Never create
again merely because a creation response was lost. Ambiguous duplicates require
resolution before activation; don't silently delete schedules.

Create/update the morning heartbeat for the configured time and planning days in
the user's timezone. Create/update the hourly heartbeat for configured active
hours and days. If the host can't express the whole active window, use an hourly
schedule plus the run skill's local-time/day gate; communicate that idle wakeups
still consume some capacity. Check displayed next-run times against the chosen
timezone; native scheduler timezone semantics must be verified on the host.

Do not show raw recurrence rules to the user. Use the tool's supported schema and
save the resulting IDs, full prompts, destination task IDs, and statuses. For
updates preserve all other existing fields, including notification policy. For
new tasks use normal notifications; do not select failed-runs-only because it
would mute desired morning plans and meaningful monitoring results.

Morning prompt content:

> Invoke $assistant-run in morning mode for installation [actual installation ID]
> at [actual absolute workspace]. Process new screenshots before planning. Fetch
> fresh calendar data, use current context and progress, and publish up to three
> achievable actions for today. Manage only this assistant's calendar blocks.
> Ask at most two consequential questions, save them, and continue unrelated work.
> If today's morning run was missed, plan for the remaining time. Read the skill
> and workspace on every run; don't rely solely on this conversation's history.

Monitor prompt content:

> Invoke $assistant-run in monitor mode for installation [actual installation ID]
> at [actual absolute workspace]. During the configured active hours, process new
> screenshots and refresh Markdown, calendar, context, and progress. Keep the plan
> stable unless a meaningful change requires an update. Stay quiet when inputs
> are unchanged or non-actionable. Notify only for a meaningful plan change, urgent
> conflict, important clarification, or actionable failure. Do not post routine
> status reports or notify merely because screenshots were processed. Persist
> questions and don't repeatedly ask unanswered questions each hour.

After either creation/update returns uncertain, inspect current schedules before
retrying. Once both IDs are verified, save them with the Schedules command. If only
one operation succeeded, retain its returned ID in a private setup request/result
file immediately and reconcile it by marker before proceeding. Don't report full
activation while the second schedule is missing.

Pause/resume via native updates with full preserved fields, then save status.
Local schedules require the computer awake, app running, paths accessible, and
working connector authentication. Missed runs are handled when the next actual
invocation happens; the workflow cannot promise to wake a sleeping computer.
