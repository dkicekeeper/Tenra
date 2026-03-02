---
phase: 01-safety-and-cleanup
plan: 01
subsystem: recurring-transactions
tags: [swift, concurrency, deadlock, dispatch-semaphore, transaction-store, recurring]

# Dependency graph
requires: []
provides:
  - "RecurringTransactionService deleted — 8 DispatchSemaphore.wait() deadlocks eliminated"
  - "RecurringTransactionServiceProtocol deleted — dead protocol removed"
  - "TransactionsViewModel recurring methods route through TransactionStore"
affects:
  - "03-performance — PERF-02 RecurringStore extract can now begin safely"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Async Task wrapper: synchronous VM methods wrap async TransactionStore calls via Task { @MainActor [weak self] in try? await self?.transactionStore?.method() }"
    - "No-op stub pattern: generateRecurringTransactions() is explicit no-op with comment explaining why TransactionStore handles generation"

key-files:
  created: []
  modified:
    - "AIFinanceManager/ViewModels/TransactionsViewModel.swift — recurring section rewired to TransactionStore"
    - "AIFinanceManager/Services/Cache/TransactionCacheManager.swift — stale comment removed"
  deleted:
    - "AIFinanceManager/Services/Transactions/RecurringTransactionService.swift — 559 LOC deleted"
    - "AIFinanceManager/Protocols/RecurringTransactionServiceProtocol.swift — 85 LOC deleted"

key-decisions:
  - "Delete RecurringTransactionService entirely rather than partial fix — deadlock risk too high for targeted patch on @MainActor"
  - "generateRecurringTransactions() becomes deliberate no-op stub with comment — TransactionStore.createSeries/updateSeries already handles generation"
  - "Both notification handlers (.recurringSeriesCreated / .recurringSeriesChanged) emptied — TransactionStore mutations are the source of truth, re-triggering from VM was redundant"

patterns-established:
  - "Async VM wrapper: wrap async throws TransactionStore methods in Task { @MainActor [weak self] in try? await self?.transactionStore?.method() } — maintains synchronous call-site signatures"
  - "No-op stub with explanation: when removing an operation, keep the method signature with a comment rather than deleting the method — preserves call-site compatibility"

requirements-completed:
  - SAFE-01
  - SAFE-02

# Metrics
duration: 7min
completed: 2026-03-02
---

# Phase 1 Plan 1: Remove RecurringTransactionService Deadlock Risk Summary

**Deleted 644 LOC of DispatchSemaphore deadlock risk; TransactionsViewModel recurring methods now route through TransactionStore with zero blocking calls on @MainActor**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-02T18:15:32Z
- **Completed:** 2026-03-02T18:22:41Z
- **Tasks:** 2
- **Files modified:** 3 (1 modified, 2 deleted)

## Accomplishments
- Eliminated 8 `DispatchSemaphore.wait()` calls that were live deadlock risks on `@MainActor` — the semaphore pattern blocks the calling thread waiting for a Task to signal, but if the Task needs the same MainActor thread to execute, the signal never fires
- Deleted `RecurringTransactionService.swift` (559 LOC) and `RecurringTransactionServiceProtocol.swift` (85 LOC) — fully deprecated since Phase 9; all real state mutations were no-ops against the read-only `recurringSeries` computed property
- Rewired all 8 call sites in `TransactionsViewModel` recurring section to use `TransactionStore` directly via async `Task` wrappers, maintaining synchronous method signatures for backward compatibility

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewire TransactionsViewModel recurring methods through TransactionStore** - `35600e1` (refactor)
2. **Task 2: Delete RecurringTransactionService.swift and RecurringTransactionServiceProtocol.swift** - `7fb684e` (fix)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `AIFinanceManager/ViewModels/TransactionsViewModel.swift` — Removed `recurringService` and `recurringGenerator` properties; replaced all 8 recurring call sites with `TransactionStore` async wrappers; removed `RecurringTransactionServiceDelegate` extension conformance; emptied both notification handlers; removed stale cache invalidation from `cleanupDeletedAccount()`
- `AIFinanceManager/Services/Cache/TransactionCacheManager.swift` — Removed stale comment referencing deleted `RecurringTransactionServiceDelegate`
- `AIFinanceManager/Services/Transactions/RecurringTransactionService.swift` — DELETED (559 LOC)
- `AIFinanceManager/Protocols/RecurringTransactionServiceProtocol.swift` — DELETED (85 LOC)

## Decisions Made
- Both notification handlers (`.recurringSeriesCreated` and `.recurringSeriesChanged`) emptied to no-ops rather than wiring new generation calls — `TransactionStore.createSeries()` and `updateSeries()` already generate transactions internally; re-triggering from `TransactionsViewModel` was redundant duplication
- `generateRecurringTransactions()` kept as an explicit no-op method stub — `AppCoordinator` calls it during `initialize()`; making it a no-op is correct since `TransactionStore.loadData()` handles recurring data loading; removing the method would require AppCoordinator changes outside this plan scope

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed stale RecurringTransactionServiceDelegate comment from TransactionCacheManager**
- **Found during:** Task 2 (post-deletion grep sweep)
- **Issue:** `TransactionCacheManager.swift` had a comment `// These properties exist only for legacy RecurringTransactionServiceDelegate compatibility.` referencing the now-deleted protocol
- **Fix:** Removed the stale comment line; kept the `@available(*, deprecated)` marker on the property itself
- **Files modified:** `AIFinanceManager/Services/Cache/TransactionCacheManager.swift`
- **Verification:** `grep -r "RecurringTransactionServiceDelegate"` returns 0 matches
- **Committed in:** `7fb684e` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - stale comment cleanup)
**Impact on plan:** Cosmetic fix only. No scope creep.

## Issues Encountered
- `PBXFileSystemSynchronizedRootGroup` project format (Xcode 16's folder-sync mode) — no per-file pbxproj entries needed; deleting files from disk is sufficient. The plan's sed-based pbxproj edit step was skipped because there were no entries to remove.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 1 Plan 2 can begin immediately
- SAFE-01 and SAFE-02 requirements are complete
- Phase 3 blocker resolved: `RecurringStore` extract (PERF-02) can now proceed safely — no competing deprecated service exists

---
*Phase: 01-safety-and-cleanup*
*Completed: 2026-03-02*
