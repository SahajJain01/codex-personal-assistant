# Personal Assistant development

Read README.md and docs/architecture.md before changing runtime behavior.
Use Context7 before implementing or debugging third-party tools or APIs.
Runtime supports Windows PowerShell 5.1/7 and the installed Hermes Python environment.
Use the Hermes Google Workspace skill's authentication; do not implement OAuth or
introduce a separate AI service. Personal data stays outside this repository.
Run the PowerShell suite, PSScriptAnalyzer, Python unittest suite and pinned Ruff
commands from README.md. Never test against real user calendars or schedules.
