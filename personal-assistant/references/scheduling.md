# Native Hermes schedules

Use the installed `cronjob` tool, inspect its current schema, and create two jobs
with `skills: ["personal-assistant"]` and `workdir` set to the absolute private
workspace. Jobs run in fresh sessions; neither conversation history nor optional
continuity replaces reading durable context. Keep the configured Hermes model.

Before creation, call cronjob list and match saved IDs, installation ID, workspace,
and mode in prompts. Reuse/update a unique match. Do not recreate after a timeout;
list again and reconcile. Keep unrelated jobs intact. Pause old Codex automations
on their original host before migrating; saved old thread IDs are not Hermes job IDs.

Morning: use a five-field cron expression for the configured planning days and time.
Monitor: use hourly cron during configured hours/days. For partial-hour boundaries,
the run reference must also gate using the workspace's local time. Verify Hermes's
resolved timezone (HERMES_TIMEZONE, then config.yaml timezone, then host local time)
matches configuration. This release does not assume per-job timezone support. If
it differs, resolve that with the user before activation; changing the profile zone
would affect unrelated jobs. Read back actual next-run times, including DST behavior.

Use native tool fields, never write cron/jobs.json. Set a descriptive name containing
the installation ID and mode. Use `attach_to_session: true` for supported connected
chat delivery. This makes delivered output continuable, not a shared execution
session. Store the returned job ID, host=hermes, kind=morning/monitor, deliver,
full prompt and status=ACTIVE/PAUSED using Schedules. Save each returned result
privately immediately, even when the second job has not yet been created.

Delivery is an explicit installation preference:
- `local`: save output only; the user must inspect it in Hermes/local output.
- `origin`: only when creating from the user's verified connected chat.
- An explicit supported platform/chat ID: only the user's selected destination.
Do not select `all` or a bot-to-bot destination. No new outbound channel is implied.

Morning prompt, replacing brackets with actual values:
> Load personal-assistant in morning mode for installation [ID] at [absolute path].
> Read references/run.md and current durable context. Process new screenshots first,
> read fresh calendars, then publish at most three achievable actions for remaining
> time today. Manage only owned blocks. Persist at most two useful questions and
> include them in the final plan; do not wait for a reply inside this cron run.

Monitor prompt:
> Load personal-assistant in monitor mode for installation [ID] at [absolute path].
> Follow references/run.md, including active-hours/day gates and missed-morning
> catch-up. Refresh sources, screenshots, calendar and saved context. Preserve a
> useful plan unless a material change requires revision. Notify only for meaningful
> plan changes, urgent conflicts, important questions or actionable failures.
> Persist questions without repeating them hourly. After releasing the lease, return
> exactly [SILENT] when nothing actionable changed, including outside active hours.

Run `hermes cron status` and `hermes cron doctor` to diagnose scheduler health.
The Hermes gateway must run and the computer must stay awake. Use the documented
Hermes gateway setup for the target version; no custom daemon or Windows task is
provided here. Do not claim activation merely because job records exist.

Pause/resume/remove using cronjob actions on the verified recorded IDs. Read back
changes and save status. Preview performs no calendar/source writes or scheduling.
A missed morning is handled by the next active run for the remaining day; there
is no promise to wake a sleeping computer. An unchanged successful monitor returns
exactly `[SILENT]`; this suppresses delivery but preserves the native run log.
