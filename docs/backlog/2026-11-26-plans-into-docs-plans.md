---
status: ready
type: chore
priority: 3
size: m
created: 2026-11-26
updated: 2026-11-26
---
# Move the plans in flight into docs/plans/ with their headers

Why: the project standard keeps designs and plans in `docs/plans/<date>-<topic>.md` with a status
header, so the Warehouse panel can read them. Tenra's plans in flight still sit flat
(`docs/plan-<topic>.md`): they are cited by name from some fifty code comments, scripts and
scheduled tasks, so they were left in place when the docs moved to the standard (2026-11-26).

Done when:
- each plan with an end (`plan-assets-roadmap`, `plan-assistant-ios27`, `plan-investments`,
  `plan-notification-capture`, `plan-release-1.9`, `plan-ten-agent`, `plan-ten-gamification`,
  `plan-threads-videos`, `plan-usage-events`) is either archived when it lands or moved to
  `docs/plans/` with a header, and every citation of its old path is updated in the same commit;
- `plan-growth.md` and `plan-sales.md` stay flat: they are standing documents without an end.

Notes: do it one plan at a time, when a session works on that plan anyway; a rename that touches
Swift comments starts a macOS build.
