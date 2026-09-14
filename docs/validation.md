# Validation record — 2026-09-14

## Verified locally

- Windows PowerShell 5.1: all 20 deterministic scenarios passed.
- PowerShell 7: all 20 deterministic scenarios passed.
- PSScriptAnalyzer 1.24.0 formatting and warning/error analysis.
- Built-in Codex plugin validator and all three skill validators.
- Isolated personal-marketplace registration and repeat installation, preserving
  unrelated entries. This test does not change the real user's Codex installation.
- Release archive check includes the `.codex-plugin/plugin.json` manifest.

The suite covers initialization, private-state isolation, concurrent runs, stale
drafts, plan/action/question constraints, screenshot duplication and changed bytes,
unavailable sources, clarifications, explicit source progress, UTF-8 preservation,
projection recovery, interrupted source preparation, committed-context recovery,
stale calendars, overlaps, lost connector responses, owned create/update/delete,
recreation after assistant removal, user overrides, outages, schedule records,
and repeat installation. Calendar observations and schedule IDs are synthetic.

Run `powershell -NoProfile -File tests/Run-Tests.ps1`. It retains isolated evidence
in a generated system-temporary directory and prints that absolute path. No test
deletes user files, calls Google, or activates real schedules.

## Independent behavioral evaluation

A separate evaluator read the skills, inspected three synthetic screenshots with
native image viewing before reading the backlog, and produced an initial plan and
an update. It did not read the evaluation rubric/expected answers. No external
tools were called. Outcome: all rubric checks satisfied; no blocking skill ambiguity.
See [the evaluated example](example-session.md).

This establishes a small realistic behavioral sample, not a statistical guarantee
of future model decisions. The deterministic suite validates bookkeeping separately.

## Target-machine integration checklist

These checks require actual installation inputs and are not claimed as completed
by the local fixture suite:

- [ ] Confirm actual Markdown paths and synced screenshot folders are readable.
- [ ] Confirm actual screenshot formats render with the target Codex image tool.
- [ ] Authenticate the intended Google account through its connector.
- [ ] List selected calendars, verify writable role, and finish a 14-day event read.
- [ ] Verify IANA/Windows timezone agreement, recurrence, all-day and busy/free behavior.
- [ ] On a designated test calendar, create/read/move/read/delete/verify one private
      solo block using the operation journal. Never use a production calendar as
      an implicit test calendar.
- [ ] Preview a real daily plan and verify its three-action/capacity limits.
- [ ] Create/reconcile the two native schedules and verify next-run times and IDs.
- [ ] Trigger one native scheduled run with real inputs and verify saved output.
- [ ] Repeat an unchanged hourly check and verify notification suppression on the host.
- [ ] Reply with progress/context, verify persistence, and inspect the revised plan.
- [ ] Pause/resume both schedules and confirm state preservation.

If no test calendar is designated, leave its trial pending for setup; do not
mislabel a simulated connector lifecycle as live validation. Native automation
notification behavior, account permissions, app availability, and connector schema
compatibility are verified on the target machine rather than assumed by the package.
