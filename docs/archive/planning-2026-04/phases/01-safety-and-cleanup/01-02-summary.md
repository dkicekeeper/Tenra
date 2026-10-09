---
phase: 01-safety-and-cleanup
plan: 02
subsystem: transactions
tags: [swift6, concurrency, dateformatter, cleanup, tombstone]

# Dependency graph
requires: []
provides:
  - Thread-safe DateFormatter declaration in TransactionQueryService (@MainActor private static let)
  - Removed empty tombstone files TransactionConverterService.swift and TransactionConverterServiceProtocol.swift
affects:
  - 01-safety-and-cleanup
  - Any future work touching TransactionQueryService or CSV import

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@MainActor private static let for DateFormatter in @MainActor classes (not nonisolated(unsafe))"

key-files:
  created: []
  modified:
    - Tenra/Services/Transactions/TransactionQueryService.swift
  deleted:
    - Tenra/Services/CSV/TransactionConverterService.swift
    - Tenra/Protocols/TransactionConverterServiceProtocol.swift

key-decisions:
  - "Use @MainActor private static let (not nonisolated(unsafe)) for DateFormatter on @MainActor classes — matches CLAUDE.md rule and eliminates data race risk"
  - "Delete tombstone files immediately — no live code referenced them; only comments in EntityMappingService and CSVImportCoordinatorFactory mention the merge"

patterns-established:
  - "DateFormatter pattern: @MainActor private static let on @MainActor classes; nonisolated(unsafe) is a code smell"

requirements-completed:
  - SAFE-03
  - CLN-01
  - CLN-02

# Metrics
duration: 4min
completed: 2026-03-02
---

# Phase 1 Plan 02: DateFormatter Race Fix + Tombstone Deletion Summary

**Replaced `nonisolated(unsafe)` with `@MainActor` on `TransactionQueryService.dateFormatter` and deleted two empty tombstone Swift files left over from the Phase 37 service merge.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-02T18:15:01Z
- **Completed:** 2026-03-02T18:18:21Z
- **Tasks:** 2
- **Files modified:** 1 modified, 2 deleted

## Accomplishments

- Fixed SAFE-03: `TransactionQueryService.dateFormatter` now declared `@MainActor private static let` — eliminates the `nonisolated(unsafe)` suppression that hid a potential data race warning without preventing it
- Fixed CLN-01: Deleted `Tenra/Services/CSV/TransactionConverterService.swift` (tombstone, no body)
- Fixed CLN-02: Deleted `Tenra/Protocols/TransactionConverterServiceProtocol.swift` (tombstone, no body)
- Confirmed neither tombstone file was referenced in `project.pbxproj` or any active Swift source (only historical comments in `EntityMappingService.swift` and `CSVImportCoordinatorFactory.swift`)
- Full build passed with zero errors after both tasks

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix DateFormatter declaration in TransactionQueryService** - `b904e16` (fix)
2. **Task 2: Delete tombstone files TransactionConverterService and TransactionConverterServiceProtocol** - `a5832a0` (chore)

**Plan metadata:** (final docs commit below)

## Files Created/Modified

- `Tenra/Services/Transactions/TransactionQueryService.swift` — Changed `nonisolated(unsafe) private static let dateFormatter` to `@MainActor private static let dateFormatter`; updated comment to explain the correct isolation reason
- `Tenra/Services/CSV/TransactionConverterService.swift` — DELETED (was empty tombstone)
- `Tenra/Protocols/TransactionConverterServiceProtocol.swift` — DELETED (was empty tombstone)

## Decisions Made

- Chose `@MainActor private static let` over other options (computed var, instance let) — static let avoids re-lookup overhead in tight loops; @MainActor matches the class isolation; this is the pattern documented in CLAUDE.md
- Deleted tombstone files without creating a replacement — the actual implementation already lives in `EntityMappingService` since Phase 37; keeping empty files only created confusion

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The `project.pbxproj` contained zero references to either tombstone file (they were never added to the Xcode project after the merge), so no pbxproj editing was required. Build passed on first attempt after each task.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- SAFE-03, CLN-01, CLN-02 complete
- Phase 01-03 (or the next plan in this phase) can proceed
- No blockers introduced

## Self-Check: PASSED

- FOUND: `Tenra/Services/Transactions/TransactionQueryService.swift` exists and contains `@MainActor private static let dateFormatter`
- FOUND (deleted): `TransactionConverterService.swift` does not exist
- FOUND (deleted): `TransactionConverterServiceProtocol.swift` does not exist
- FOUND: commit `b904e16` (Task 1)
- FOUND: commit `a5832a0` (Task 2)

---
*Phase: 01-safety-and-cleanup*
*Completed: 2026-03-02*
