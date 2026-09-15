# Migrating an existing Codex assistant

Version 0.2.0 targets Nous Research Hermes Agent. The previous Codex release remains
in Git history at commit 880b5c496ed8d73af2671319d55c9bc2906b3789.

1. On the old Codex host, pause both recorded automations and verify no run remains
   active. Hermes cannot pause Codex automations. Do this before activating Hermes.
2. Back up the complete private workspace. Keep the same absolute path when possible;
   paths inside source/task records are not automatically rewritten after a move.
3. Install the Hermes skill in the intended profile. Configure Hermes model/vision
   and Google Workspace Calendar authentication separately; never transfer tokens.
4. Read the existing workspace with Assistant.ps1 Read. Init is idempotent. Do not
   replace installationId, tasks, screenshot hashes, questions, block mappings or
   journal. Schema 1 stays compatible. Recover an abandoned lease only after the
   old process is confirmed stopped. Reconcile unresolved calendar operations first.
5. Use the same Google account/calendars. Verify full normalized block fields before
   changing anything. Legacy event IDs are retained; only new bridge operations use
   deterministic IDs. If an event differs, treat it as a user override. Do not
   reset fingerprints just to make an update pass. The richer Hermes fingerprint
   can conservatively protect a legacy block as an override for the rest of its
   day; new blocks record the complete bridge normalization.
6. Review timezone, remaining-day preview and new delivery destination. Create or
   reconcile the Hermes jobs by installation/workspace/mode, save their actual IDs
   with host=hermes. Prior Codex schedule records remain in historical snapshots.
7. Verify next runs and gateway health, then activate. Keep the original backups.

Never run old and new schedules concurrently. Reinstalling the skill never moves
or clears private state. To roll back, pause Hermes jobs first and keep a backup of
all progress since migration; inspect compatibility before using the older runtime.
