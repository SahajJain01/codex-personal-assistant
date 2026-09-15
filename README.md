# Hermes Personal Assistant

A Windows-native skill bundle for **Nous Research Hermes Agent**. It turns local
Markdown to-dos, synced phone screenshots and Google Calendar into **up to three
achievable daily actions**, with persistent context and private task blocks.

## Install on your target computer

1. Install/configure Hermes Agent and its model and vision access.
2. Download this repository and open a Hermes session in the repository directory.
3. Paste [BOOTSTRAP.md](BOOTSTRAP.md). Setup collects source paths, calendar selection,
   a private workspace, timezone, schedule, availability and delivery preferences.
4. Review the configuration summary and preview. Setup then reconciles two native
   cron jobs: a morning plan and hourly monitoring.

You can install the self-contained skill manually:

```powershell
powershell -NoProfile -File tools/Install.ps1
# For a particular Hermes profile:
powershell -NoProfile -File tools/Install.ps1 -HermesHome 'C:\path\to\hermes-profile'
```

Then ask Hermes: **Load personal-assistant and set it up.** Installation copies the
skill only; it does not connect accounts, activate jobs or read your personal inputs.
The installer honors HERMES_HOME, otherwise uses Windows LocalAppData/hermes. For a
named profile, explicitly supply its resolved directory. Updates preserve unrelated
skills and keep old releases outside skill discovery in assistant-releases.

Requirements: Windows, PowerShell 5.1+, Hermes with skills, cronjob and vision_analyze,
a working Google Workspace skill with Calendar authorization and its Python Google
API client dependencies, and a locally synced screenshot folder. Setup uses Hermes's
existing Google authentication; a new Google account setup may need a Desktop OAuth
client credential. Credentials never belong in this repository or assistant state.
Keep the **Hermes gateway running and computer awake** for scheduled runs.

No Codex installation, separate AI service, database or dashboard is required.
Hermes's configured model/provider and vision services still process inputs normally.
Screenshot arrival can be real time; extraction happens hourly, before planning or
on demand. Successful image extraction is reused by content hash.

## Daily use

Say “Plan the rest of my day”, “I finished the first action”, “I only have 30 minutes
today”, or “That screenshot was inspiration”. The assistant preserves evidence and
task identities while updating context, questions, progress and the current plan.

Every scheduled run is a fresh Hermes session. The private workspace, rather than
chat history, holds context.md, tasks.md, questions.md, inferred-actions.md, today.md,
plans and an immutable journal. Original to-do Markdown remains ordinary Markdown.
Source checkboxes change only after an explicit completion report and exact match.

Planning uses at most 60% of available task time. Large goals become concrete steps
with completion conditions. At most two useful questions appear per run; unanswered
questions do not block unrelated work. Unchanged hourly runs return Hermes's native
[SILENT] marker to suppress delivery.

Choose a connected user chat for delivered plans/questions, or `local` for saved
output only. Chat delivery can attach output to a continuable session. Replies load
the same durable workspace even when received in a different session.

Calendar writes use the bundled bridge and Hermes-managed credentials. It finishes
pagination, rechecks free time, journals each dispatch, uses conditional updates,
and verifies results. Only owned private solo blocks are managed. User edits and
deletions remain overrides. No task execution, invitations or messages to others.

## Maintenance and development

Ask Hermes to load personal-assistant in setup mode to diagnose, pause or resume.
Pause both jobs before upgrades, reinstall, verify the loaded release, then resume.
For uninstall, remove only the two recorded jobs and installed skill; retain private
state and calendar blocks unless you explicitly request cleanup.

See [migration](docs/migration.md), [architecture/recovery](docs/architecture.md),
[validation and target checklist](docs/validation.md), and [example](docs/example-session.md).
The public repository keeps its original URL; version 0.2.0 is Hermes-native.

```powershell
Save-Module -Name PSScriptAnalyzer -RequiredVersion 1.24.0 -Path .tools -Repository PSGallery
python -m venv .tools/python
.tools/python/Scripts/python -m pip install ruff==0.12.12
powershell -NoProfile -File tools/Check.ps1
powershell -NoProfile -File tests/Run-Tests.ps1
.tools/python/Scripts/python -m ruff check personal-assistant/scripts tests
.tools/python/Scripts/python -m ruff format --check personal-assistant/scripts tests
python -m unittest discover -s tests -p 'test_*.py'
powershell -NoProfile -File tools/Package.ps1
```

Ruff and PSScriptAnalyzer are development-only. Test calendars and API responses are
synthetic; live account and delivery validation remains part of target setup.

Host references: [Hermes skills](https://hermes-agent.nousresearch.com/docs/developer-guide/creating-skills),
[cron](https://hermes-agent.nousresearch.com/docs/user-guide/features/cron),
[Google Workspace](https://hermes-agent.nousresearch.com/docs/user-guide/skills/google-workspace).
