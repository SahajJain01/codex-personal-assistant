# Codex Personal Assistant

A Windows Codex plugin that turns Markdown to-dos, synced phone screenshots, and
Google Calendar into **up to three achievable daily actions**. It maintains context
across runs and manages only its own private calendar blocks.

## Install on your target computer

1. Download this repository and open it in Codex desktop.
2. Paste the contents of [BOOTSTRAP.md](BOOTSTRAP.md) into a task.
3. Supply your source paths, private workspace, calendar selection, and schedule.
4. Continue setup in the private workspace when prompted. The setup skill verifies
   capabilities, previews the plan, and creates morning and hourly native schedules.

You can also run `powershell -NoProfile -File tools/Install.ps1` to register and
install the plugin, then open a Codex task in your private workspace and invoke
`$assistant-setup`. Installation does not itself read personal inputs, connect an
account, or activate schedules. Those require your target-machine configuration.

Requirements: Windows PowerShell 5.1+, Codex desktop with native scheduling and
image viewing, a connected Google Calendar plugin, and a local screenshot folder
already synced by your phone's sync solution. Runtime has no additional package,
server, database, or AI API-key requirement. Keep the computer awake and app running.

The plugin supplies workflows and local reliability helpers; Codex performs
semantic interpretation and connector calls. Hourly screenshot processing is not
instantaneous even when files arrive in real time.

## Use it

Keep one ongoing assistant task. Say "Plan the rest of my day", "I finished the
first action", "I only have 30 minutes today", or "That screenshot was inspiration".
Ask it to change priorities, remember a constraint, or defer a question. Corrections
update current context without erasing prior evidence or historical plans.

Your workspace contains context.md, tasks.md, questions.md, inferred-actions.md,
today.md, plans, and an immutable transaction journal. These are readable views;
update them through the assistant. Edit your original to-do Markdown normally.
Unanswered questions don't block unrelated tasks. Hourly checks notify only on a
meaningful change, important question, or actionable failure.

The assistant creates private solo task blocks, verifies them, and respects manual
edits/deletions. It doesn't rearrange other appointments, invite people, send
messages, or execute your to-do tasks. Source checkbox writes require your explicit
progress report and an exact matching unchecked line.

## Maintenance

Ask `$assistant-setup` to diagnose, pause, resume, or update configuration.
Upgrades replace the plugin source while retaining private state. Previous plugin
sources are retained as backups under your profile's plugins folder. Start a new
task after reinstalling to load new skill code; use the same private workspace and
reconcile existing schedule IDs before continuing.

For uninstall: pause both native schedules, remove the plugin, and retain your
private workspace. Calendar-block cleanup is a separate explicit request.
See [architecture and recovery](docs/architecture.md) and [validation](docs/validation.md).

## Develop and validate

```powershell
Save-Module -Name PSScriptAnalyzer -RequiredVersion 1.24.0 -Path .tools -Repository PSGallery
powershell -NoProfile -File tools/Check.ps1 -Fix
powershell -NoProfile -File tools/Check.ps1
powershell -NoProfile -File tests/Run-Tests.ps1
```

The pinned module is a development-only formatter/analyzer. Tests use temporary
Windows directories and simulated connector observations; they do not call Google
or activate native schedules. Live integration validation is explicitly separate.

Design references: [Codex skills](https://learn.chatgpt.com/docs/build-skills),
[native schedules](https://learn.chatgpt.com/docs/automations?surface=app), and
[plugins](https://learn.chatgpt.com/docs/plugins). Tool schemas verified during
development may differ on a target host; setup checks actual available capabilities.
