# Validation record — Hermes conversion, 2026-09-15

## Local verification

- Windows PowerShell 5.1 and PowerShell 7: 20 deterministic scenarios each.
- PSScriptAnalyzer 1.24.0 formatting and warning/error analysis.
- Python: nine calendar transport/Windows interop tests; Ruff 0.12.12 formatting and lint.
- Installed Hermes v0.20.6: native skill discovery, all three reference modes, and
  cron create/update/pause/remove in an isolated temporary profile. No gateway ran,
  no job executed, and no real profile, account or delivery destination was changed.
- Repeat installation preserves private memory and unrelated skills. Release
  packaging contains the self-contained Hermes SKILL.md and support files.

PowerShell covers state isolation, run leases, stale drafts, bounded plans,
screenshot deduplication, progress and clarification, source-write recovery,
calendar ownership, overrides, replay rejection and repeated setup. Python tests
cover complete pagination, cancelled/free/declined/all-day behavior, fresh conflicts,
private deterministic creates, conditional updates/deletes, user edits, lost
responses and failed ETags. Google responses and schedule records are synthetic.

Reproduce with the commands in README.md. To check a local Hermes install without
using its account or starting a gateway:

```text
<Hermes Python> tests/hermes_compat.py --source <Hermes installation directory>
```

This compatibility check retains a temporary isolated profile with local-only jobs
removed at the end. It tests host mechanics, not model reasoning or live delivery.

## Behavioral fixture

The previous Codex version had an independent screenshot/planning evaluation; its
example remains in [example-session.md](example-session.md). Planning invariants
are retained in the Hermes run/update references. That historical evaluation is
not presented as a live Hermes model evaluation. Use tests/New-EvaluationFixture.ps1
and tests/fixtures/evaluation.md for a fresh target-model trial.

## Target-machine checklist — pending real inputs

- [ ] Verify active Hermes profile and intended model/vision tools.
- [ ] Confirm actual Markdown paths and screenshot folders; view one real image.
- [ ] Authenticate the intended Google account using Hermes google-workspace.
- [ ] Verify bridge dependencies and full paginated 14-day calendar reads.
- [ ] Verify write role and chosen calendar, IANA/Windows/Hermes timezone agreement.
- [ ] Test create/read/move/read/delete/absence on an explicitly designated test
      calendar; do not treat production calendars as implicit test fixtures.
- [ ] Preview a real plan and inspect action count, breakdown and capacity.
- [ ] Confirm user delivery destination, or explain local output is save-only.
- [ ] Reconcile two native jobs and inspect next-run times and gateway health.
- [ ] Run one scheduled plan, then verify unchanged-monitor delivery suppression.
- [ ] Answer a question/report progress and verify durable context on the next run.
- [ ] Pause/resume and verify state preservation.
- [ ] For migration, verify old Codex schedules are paused before Hermes activation.

Live OAuth, Google writes, model image interpretation and connected-chat delivery
remain untested until the target inputs are provided. No local fixture is evidence
that the user's workflow is already active.
