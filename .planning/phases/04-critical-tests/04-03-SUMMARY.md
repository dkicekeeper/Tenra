---
phase: 04-critical-tests
plan: 03
subsystem: testing
tags: [coredata, swift-testing, in-memory-store, round-trip, serialized-suite]

requires:
  - phase: 04-critical-tests
    provides: existing test infrastructure (Swift Testing, AIFinanceManagerTests target)

provides:
  - CoreData round-trip integration test (TEST-04) — 6 tests covering TransactionEntity save/reload cycle

affects:
  - future CoreData schema migrations (catch regressions early)
  - future entity field additions (test ensures all fields verified)

tech-stack:
  added: []
  patterns:
    - ".serialized suite trait + unique UUID store URL for NSInMemoryStoreType isolation across parallel Swift Testing runs"
    - "performAndWait block pattern for NSManagedObjectContext thread safety in synchronous tests"
    - "context.reset() after save to evict identity map and force true reload from store"

key-files:
  created:
    - AIFinanceManagerTests/CoreDataRoundTripTests.swift
  modified: []

key-decisions:
  - "Used .serialized suite trait to prevent NSInMemoryStoreType cross-test contamination — Swift Testing runs tests in parallel by default; parallel containers with same name share backing stores"
  - "Used unique UUID store URL (memory://UUID) per container to guarantee store isolation even if .serialized is ever removed"
  - "Used performAndWait instead of await MainActor.run — synchronous, avoids async test complexity, NSManagedObjectContext.viewContext is main-thread-affined so performAndWait is the correct threading primitive"

patterns-established:
  - "NSInMemoryStoreType test pattern: makeInMemoryContainer() with unique URL + .serialized suite"
  - "CoreData test threading: performAndWait for all context operations; capture results in outer scope vars then assert outside the block"

requirements-completed: [TEST-04]

duration: 8min
completed: 2026-03-02
---

# Phase 04 Plan 03: CoreData Round-Trip Tests Summary

**6-test CoreData round-trip suite using NSInMemoryStoreType with .serialized trait and UUID store URLs to prevent parallel test contamination**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-02T20:05:39Z
- **Completed:** 2026-03-02T20:14:15Z
- **Tasks:** 1 (TDD)
- **Files modified:** 1

## Accomplishments
- 6 Swift Testing tests verify the complete TransactionEntity save → reload cycle in an isolated in-memory CoreData store
- dateSectionKey auto-population via willSave() verified (Test B)
- convertedAmount nil ↔ 0.0 round-trip behavior verified (Tests C, E)
- Discovered and fixed NSInMemoryStoreType parallel contamination issue (tests were flaky until .serialized + UUID URLs added)
- Zero shared state with app's production SQLite store — fully isolated

## Task Commits

Each task was committed atomically:

1. **Task 1: CoreData round-trip tests (TEST-04)** - `a7c9020` (test)

**Plan metadata:** (to be created)

_Note: TDD task — RED phase showed flaky failures due to parallel test contamination; GREEN phase fixed with .serialized trait + unique store URLs_

## Files Created/Modified
- `AIFinanceManagerTests/CoreDataRoundTripTests.swift` - 6 round-trip tests for TransactionEntity; uses NSInMemoryStoreType with .serialized suite trait and UUID store URLs for isolation

## Decisions Made
- `.serialized` suite trait chosen to prevent NSInMemoryStoreType contamination between parallel tests — Swift Testing parallelizes by default and `NSInMemoryStoreType` containers with the same name share backing stores, causing random test failures
- UUID-based store URLs added as additional isolation layer (defense in depth)
- `performAndWait` used instead of `await MainActor.run` — cleaner for synchronous test flows, avoids async test boilerplate, correct threading primitive for NSManagedObjectContext

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed NSInMemoryStoreType parallel test contamination**
- **Found during:** Task 1 (CoreData round-trip tests) — tests were failing non-deterministically
- **Issue:** Swift Testing runs tests in parallel by default. Multiple `NSPersistentContainer(name: "AIFinanceManager")` instances with `NSInMemoryStoreType` and no explicit store URL shared the same backing store. Tests inserting different entities saw each other's data; count assertions (`count == 1`, `count == 3`) were non-deterministic.
- **Fix:** Added `@Suite(.serialized)` trait + unique `description.url = URL(string: "memory://\(UUID().uuidString)")` per container. Also replaced `await MainActor.run { try ... }` with `performAndWait` for cleaner synchronous threading.
- **Files modified:** `AIFinanceManagerTests/CoreDataRoundTripTests.swift`
- **Verification:** All 6 tests pass consistently across multiple runs
- **Committed in:** `a7c9020` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Essential fix for test correctness. Without it, tests gave false signal (random pass/fail). No scope creep.

## Issues Encountered
- NSInMemoryStoreType container isolation: plan spec mentioned per-test containers for isolation but did not anticipate Swift Testing's parallel execution model. Fixed by applying .serialized + unique URLs — standard pattern for CoreData test isolation in Swift Testing.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TEST-04 complete: CoreData round-trip coverage established
- All 6 tests passing consistently
- Pre-existing AmountFormatterTests failures (3 tests) unrelated to this plan — pre-existed before phase 04

## Self-Check: PASSED

- FOUND: `AIFinanceManagerTests/CoreDataRoundTripTests.swift`
- FOUND: `.planning/phases/04-critical-tests/04-03-SUMMARY.md`
- FOUND: commit `a7c9020`

---
*Phase: 04-critical-tests*
*Completed: 2026-03-02*
