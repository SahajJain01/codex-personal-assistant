---
name: assistant-setup
description: Install, configure, diagnose, pause, or upgrade the Windows Personal Assistant that plans from local Markdown, synced screenshots, and Google Calendar.
---

# Assistant setup

Use this for setup and configuration of this plugin. The plugin root is two
directories above this skill directory. Read [the runtime contract](../../references/runtime.md)
before operating its helpers. Read [scheduling](../../references/scheduling.md)
when creating, changing, or pausing native schedules.

## Collect and verify

1. Confirm Windows, Windows PowerShell 5.1 or newer, Codex image viewing, native
   automation tools, and Google Calendar connector tools. Use tool discovery;
   never assume the connector account on the packaging machine is the target account.
2. If installing from the repository, use its `tools/Install.ps1`. The personal
   marketplace is discovered implicitly. A new task may be needed to load skills;
   give an exact continuation instruction if the current task cannot use them.
3. Collect all input Markdown file paths and screenshot folder paths. Screenshots
   must already sync locally; do not build a phone-sync service. Explain hourly
   processing versus real-time arrival. Only scan configured folders, nonrecursively.
4. Collect a private workspace outside the plugin/repository and shared or public
   folders. Default to the user's Documents\Personal Assistant. Files and model
   processing use normal Codex services; this is not an offline model.
5. List calendars through the connector, page to completion, and have the user
   select the calendars to consider and one writable calendar. Verify its access
   role is writer/owner. Existing appointments must remain unchanged.
6. Gather IANA timezone and the corresponding Windows timezone ID; verify they
   represent the same zone (including daylight saving), never infer from an offset
   alone. Gather morning time, hourly monitoring window, planning days, task windows,
   breaks, fixed personal commitments, goals, priority notation, and action duration.
   Default to three actions, 60% capacity, 30-minute steps, daily 08:00 planning,
   09:00–20:00 monitoring, all days. Confirm defaults through the setup summary.
7. Default screenshotSince to seven days before installation, in the selected
   timezone; ask if the user wants an older backlog. Do not copy the example date.

Batch missing preferences in a short question. Existing session authorization
persists: do not ask again for the same calendar/file authority. If the user wants
different write permissions, save them in configuration.

Read each source file and report inaccessible paths. Verify one real screenshot
with the native image viewer, without committing extraction during this check.
Fetch a bounded calendar window and finish pagination; verify all-day/recurrence
details can be read. If a capability is missing, finish the usable configuration
and identify the specific blocked capability. Do not activate partially tested
calendar writes or invent successful tests.

## Initialize and activate

Create an Init request using the config example in `assets/config.example.json`,
replacing every example value. Store requests in the private workspace, never in
the plugin. The context starts with the user's goals, constraints, confirmed facts,
and an empty labeled assumptions section. Initialize with the helper. Re-running
Init preserves existing state; use Configure under a run lease to change settings.

The ongoing assistant task must run locally in the private workspace. If this is
the repository task, direct the user to open that workspace and invoke
`$assistant-setup` there; continue all independent setup work first. Do not attach
live schedules to a temporary test task or an isolated Git worktree.

Present the configuration summary and a preview with no calendar/source writes.
Follow Assistant run in preview mode to use actual inputs. Preview may save
observations and a plan in the private workspace, but must not prepare or execute
calendar operations. Label it a preview.

For a full end-to-end calendar trial, use a calendar explicitly designated by the
user for testing. Create one private solo test block, read it back, move it into
verified free time, read it back, delete it, and verify absence. Use the operation
journal protocol. Do not create test appointments on an undesignated calendar.
If there is no test calendar, verify write role and record the first real planned
block/readback as pending integration validation; report this distinction.

Then activate morning and hourly schedules using the scheduling reference. Save
and read back both schedule IDs. Existing authorization covers activation after
checks pass. Report setup complete only with actual configuration and schedule
evidence; mention the app/computer must remain running.

## Diagnose, upgrade, pause

Use Read to inspect state and existing schedule IDs. Recover can rebuild derived
Markdown after interruption. A run lease is not automatically stolen: abandon it
only after verifying the old task has stopped and cannot still call the connector.
Reconcile unresolved calendar operations before another calendar write.

For upgrades, reinstall the versioned release with tools/Install.ps1. During local
development follow the available plugin-creator cachebuster/reinstall workflow.
Never put private state in the plugin cache or replace the workspace. For pause,
update both native schedules to paused and preserve all other fields. For uninstall,
pause schedules first, remove the plugin using the native plugin manager, and retain
the private workspace unless the user explicitly asks to delete it. Existing
calendar blocks are retained unless the user requests cleanup.
