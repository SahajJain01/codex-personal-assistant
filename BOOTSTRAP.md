Set up the Hermes Personal Assistant from this repository on this Windows computer.
Read README.md, confirm the active Hermes profile, and run tools/Install.ps1 for that
profile. Load personal-assistant/SKILL.md and follow references/setup.md. Use native
Hermes skills, cronjob, vision_analyze and Google Workspace authentication.

Collect my Markdown and screenshot paths, private workspace, selected calendars,
timezone, morning time, monitoring hours, task availability, goals and preferences.
Also collect where I want plans delivered: my connected chat or local saved output.
Never use example paths, this repository or the installed skill as private storage.

If migrating an existing Codex assistant, follow docs/migration.md first. Preserve
its workspace and history and pause its old schedules before activating Hermes.

Use the existing authorization to manage only assistant-created private solo calendar
blocks and exact source checkboxes after explicit progress reports. Show a setup
summary and preview, then activate the two native cron jobs once capability checks
pass. Ask only for missing information or authentication steps actually required.
Record returned job IDs and verify the Hermes gateway and next-run times. Do not
claim activation while authentication, delivery or scheduler checks are unresolved.
