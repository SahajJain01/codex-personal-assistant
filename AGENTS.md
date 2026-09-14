# Personal Assistant development

Read README.md and docs/architecture.md before changing runtime behavior.
Use Context7 before implementing or debugging third-party tools or APIs.
Runtime supports Windows PowerShell 5.1 and PowerShell 7 on Windows.
No runtime package installation, direct Google OAuth implementation, or separate AI API.
Run `powershell -NoProfile -File tools/Check.ps1` and `powershell -NoProfile -File tests/Run-Tests.ps1`.
Personal data and test artifacts belong outside the plugin; never commit live connector responses.
