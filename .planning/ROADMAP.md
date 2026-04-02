# Roadmap: Tenra — Tech Debt & Safety Milestone

## Overview

Four phases eliminate active risks (deadlock, race conditions, dead code), harden security, close a CoreData migration gap that would crash on update, squeeze the last Insights performance win, and build the test coverage that makes future changes safe. Phases flow in dependency order: clean up the risks first, then secure, then optimize, then verify.

## Milestones

- 🚧 **Tech Debt & Safety** - Phases 1-4 (in progress)

## Phases

- [x] **Phase 1: Safety & Cleanup** - Delete deadlock-prone service, fix DateFormatter race, remove 4 dead-code files
- [x] **Phase 2: Security & Data Migration** - File protection on CoreData store, amount upper-bound validation, explicit CoreData migration model (completed 2026-03-02)
- [x] **Phase 3: Performance** - Pre-aggregate category totals in PreAggregatedData, extract RecurringStore from TransactionStore (completed 2026-03-02)
- [x] **Phase 4: Critical Tests** - Unit tests for DepositInterestService, CategoryBudgetService, RecurringTransactionGenerator edge cases, CoreData round-trip (completed 2026-03-02)

## Phase Details

### Phase 1: Safety & Cleanup
**Goal**: The codebase contains no deadlock-prone code and no deprecated dead files that obscure where logic actually lives
**Depends on**: Nothing (first phase)
**Requirements**: SAFE-01, SAFE-02, SAFE-03, CLN-01, CLN-02, CLN-03, CLN-04
**Success Criteria** (what must be TRUE):
  1. `RecurringTransactionService.swift` and `RecurringTransactionServiceProtocol.swift` are deleted; all recurring call sites in `TransactionsViewModel` route through `TransactionStore+Recurring.swift`
  2. `TransactionQueryService` declares its DateFormatter as `@MainActor private static let`; no DispatchSemaphore exists anywhere in the codebase
  3. `TransactionConverterService.swift`, `TransactionConverterServiceProtocol.swift`, deprecated Account Balance Cache section in `TransactionCacheManager.swift`, and the incomplete prefix-invalidation TODO in `UnifiedTransactionCache.swift` are all gone
  4. The app builds without errors under `SWIFT_STRICT_CONCURRENCY = targeted`
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Delete RecurringTransactionService + protocol; rewire TransactionsViewModel recurring calls to TransactionStore
- [x] 01-02-PLAN.md — Fix TransactionQueryService DateFormatter thread safety; delete TransactionConverterService tombstones
- [x] 01-03-PLAN.md — Remove deprecated Account Balance Cache from TransactionCacheManager; resolve UnifiedTransactionCache TODO

### Phase 2: Security & Data Migration
**Goal**: Financial data is protected at rest and validated at entry; a CoreData schema migration model exists so an app update cannot crash existing users
**Depends on**: Phase 1
**Requirements**: SEC-01, SEC-02, DATA-01
**Success Criteria** (what must be TRUE):
  1. CoreData SQLite store is created with `NSFileProtectionKey: .complete`; the option is visible in `CoreDataStack.swift` store configuration
  2. `AmountInputView` rejects any amount above 999,999,999.99; `AmountFormatter.validate()` is called before the value is accepted by the store
  3. An explicit CoreData mapping model exists for the version containing `MonthlyAggregateEntity` and `CategoryAggregateEntity`; upgrading from old schema to current does not crash
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md — Add NSFileProtectionComplete to CoreDataStack store description and resetAllData() path (SEC-01)
- [x] 02-02-PLAN.md — Add AmountFormatter.validate() upper-bound method; enforce in AddTransactionCoordinator (SEC-02)
- [x] 02-03-PLAN.md — Create v2→v3 xcmappingmodel bundle inside xcdatamodeld; human verify compiles (DATA-01)

### Phase 3: Performance
**Goal**: Insights `.allTime` granularity completes in under 50ms; `TransactionStore` has a separately testable `RecurringStore`
**Depends on**: Phase 1 (RecurringTransactionService deleted before RecurringStore extracted)
**Requirements**: PERF-01, PERF-02
**Success Criteria** (what must be TRUE):
  1. `PreAggregatedData.build()` computes `categoryTotals: [String: Double]` in its single O(N) pass; Insights generators use this dictionary instead of scanning transactions per granularity
  2. Insights `.allTime` wall-clock time drops from ~307ms to under 50ms (measurable via `PerformanceProfiler` in DEBUG mode)
  3. Recurring methods are in a standalone `RecurringStore` file; `TransactionStore.swift` no longer contains recurring generation or series management logic
**Plans**: 2 plans

Plans:
- [ ] 03-01-PLAN.md — Add categoryTotals to PreAggregatedData.build(); wire generateSpendingInsights to use it for .allTime (PERF-01)
- [ ] 03-02-PLAN.md — Create RecurringStore.swift; extract recurring state from TransactionStore; wire AppCoordinator (PERF-02)

### Phase 4: Critical Tests
**Goal**: The four highest-risk business-logic paths have unit tests that will catch regressions
**Depends on**: Phase 1, Phase 2 (test the cleaned-up, validated code)
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04
**Success Criteria** (what must be TRUE):
  1. `DepositInterestService` tests cover daily interest accrual, boundary dates (first/last day of month), and leap-year February
  2. `CategoryBudgetService` tests cover period boundary detection (spent exactly at limit), budget rollover between periods, and zero-transaction periods
  3. `RecurringTransactionGenerator` tests cover Feb 29 on leap year, Jan 31 monthly → Feb 28/29, and a DST-boundary generation window
  4. A CoreData round-trip test saves a `TransactionEntity` to an in-memory store and reloads it; all fields match after reload
**Plans**: 3 plans

Plans:
- [ ] 04-01-PLAN.md — DepositInterestService tests (TEST-01) + CategoryBudgetService tests (TEST-02)
- [ ] 04-02-PLAN.md — RecurringTransactionGenerator edge-case tests: Feb 28/29, DST boundary (TEST-03)
- [ ] 04-03-PLAN.md — CoreData round-trip test: save TransactionEntity to in-memory store, reload, verify fields (TEST-04)

## Progress

**Execution Order:** 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Safety & Cleanup | 3/3 | Complete    | 2026-03-02 |
| 2. Security & Data Migration | 3/3 | Complete    | 2026-03-02 |
| 3. Performance | 2/2 | Complete    | 2026-03-02 |
| 4. Critical Tests | 3/3 | Complete    | 2026-04-02 |
