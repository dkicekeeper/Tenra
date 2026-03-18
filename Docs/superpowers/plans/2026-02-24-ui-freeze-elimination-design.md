# UI Freeze Elimination — Home & Analytics

**Date:** 2026-02-24
**Phase:** 31
**Status:** Approved

---

## Problem

Three independent UI freezes reported on iPhone 17 (A18) with ~19k transactions:

| Freeze | Symptom | Duration |
|--------|---------|----------|
| A | App launch — no first frame | 2–4s |
| B | Skeleton → real content transition jank | ~275ms |
| C | Analytics tab first open hangs | 1–3s |

---

## Root Causes

### Freeze A — CoreData Pre-Warm

`CoreDataStack.persistentContainer` is a `lazy var`. Its `loadPersistentStores()` call runs
**synchronously on MainActor** when `CoreDataRepository()` is first created inside
`AppCoordinator.init()`. Opening the SQLite file blocks the render thread before the first
frame is produced.

```
MainActor (AppCoordinator.init)
  └── CoreDataRepository.init()
       └── CoreDataStack.shared.viewContext
            └── CoreDataStack.shared.persistentContainer   ← lazy var
                 └── NSPersistentContainer.loadPersistentStores()  ← BLOCKS ~300ms
```

### Freeze B — Summary Computation on MainActor

`updateSummary()` in ContentView calls `filterByTime()` + `calculateSummary()` synchronously
on MainActor (~275ms for 19k transactions). Even with the 80ms debounce added in Phase 30,
the computation itself blocks the render thread at the exact moment the skeleton lifts.

### Freeze C — InsightsService @MainActor Actor Hop

`InsightsService` is declared `@MainActor`. When `InsightsViewModel.loadInsightsBackground()`
calls `await service.computeGranularities(...)` inside a `Task.detached`, Swift automatically
hops **back to MainActor** to execute the method. The entire 1–3s insight computation runs on
the UI thread despite being inside a "background" task.

```swift
// InsightsViewModel.loadInsightsBackground()
recomputeTask = Task.detached {          // ← off MainActor ✓
    let result = await service           // ← @MainActor → HOP BACK ✗
        .computeGranularities(...)       // ← runs on MainActor, blocks UI
}
```

**Non-issue confirmed:** `makeBalanceSnapshot()` calls `calculateTransactionsBalance(for:)` which
is O(1) — it reads directly from `BalanceCoordinator.balances` dictionary. Not a bottleneck.

---

## Solution: Two-Phase Approach

### Phase 1 — Three Targeted Fixes (Approach A)

#### Fix A: CoreData Pre-Warm

Pre-warm `CoreDataStack.persistentContainer` on a background thread **before** `AppCoordinator`
is created, so SQLite is open by the time init() runs.

**Files changed:**
- `CoreData/CoreDataStack.swift` — add `preWarm()` method
- `AppDelegate.swift` — call `CoreDataStack.shared.preWarm()` as first line of `didFinishLaunchingWithOptions`
- `AIFinanceManagerApp.swift` — make `coordinator` optional (`AppCoordinator? = nil`), create it after pre-warm completes via `.task`; show `Color(.systemBackground).ignoresSafeArea()` while nil

```swift
// CoreDataStack
func preWarm() {
    Task.detached(priority: .userInitiated) {
        _ = CoreDataStack.shared.persistentContainer
    }
}

// AppDelegate
func application(...) -> Bool {
    CoreDataStack.shared.preWarm()   // first line
    // ...
}

// AIFinanceManagerApp
@State private var coordinator: AppCoordinator? = nil

var body: some Scene {
    WindowGroup {
        Group {
            if let coordinator {
                MainTabView()
                    .environment(timeFilterManager)
                    .environment(coordinator)
                    .environment(coordinator.transactionStore)
            } else {
                Color(.systemBackground).ignoresSafeArea()  // system launch screen already visible
            }
        }
        .task {
            await Task.detached(priority: .userInitiated) {
                _ = CoreDataStack.shared.persistentContainer  // await warm if not done
            }.value
            coordinator = AppCoordinator()
        }
    }
}
```

**Expected result:** CoreData loads in parallel with system launch screen. First app frame
appears with coordinator ready and zero SQLite latency.

---

#### Fix B: Summary Computation Off-Thread

Extract filtering + summary calculation into a `nonisolated static func` that works only on
value-type parameters, callable from `Task.detached`.

**Files changed:**
- `Services/Transactions/SummaryCalculator.swift` — new `enum` with static compute function
- `Views/Home/ContentView.swift` — `updateSummary()` uses `Task.detached` + `SummaryCalculator`

```swift
// SummaryCalculator.swift — new file
enum SummaryCalculator {
    nonisolated static func compute(
        transactions: [Transaction],
        filter: TimeFilter,
        currency: String
    ) -> Summary {
        // Reuses logic from TransactionFilterCoordinator + TransactionQueryService
        // Pure function — no stored state, no actor dependencies
    }
}

// ContentView.updateSummary()
private func updateSummary() {
    let transactions = viewModel.allTransactions
    let filter       = timeFilterManager.currentFilter
    let currency     = viewModel.appSettings.baseCurrency

    summaryUpdateTask?.cancel()
    summaryUpdateTask = Task.detached(priority: .userInitiated) {
        let summary = SummaryCalculator.compute(
            transactions: transactions,
            filter: filter,
            currency: currency
        )
        await MainActor.run { [weak self] in
            self?.cachedSummary = summary
        }
    }
}
```

`TransactionsSummaryCard` already shows `ProgressView()` when `cachedSummary == nil` — no
UI change needed. The card shows real data as soon as the background task completes (~15–30ms
at 19k transactions on a background thread).

---

#### Fix C: InsightsService De-Isolation

Remove `@MainActor` from `InsightsService` class declaration. Computation methods only use
their value-type parameters — they don't need MainActor. Methods that must access
MainActor resources (e.g. `transactionStore`) get explicit `@MainActor` annotation.

**Files changed:**
- `Services/Insights/InsightsService.swift` — remove `@MainActor` from class; add explicit `@MainActor` to methods that access actor-isolated dependencies; ensure `computeGranularities` and `computeHealthScore` are nonisolated
- `Services/Insights/InsightsCache.swift` — verify thread safety (add `@unchecked Sendable` if needed)
- `Services/Transactions/TransactionCurrencyService.swift` — verify `Sendable` compliance
- `Services/Cache/TransactionCacheManager.swift` — verify `Sendable` compliance

**Expected result:** `await service.computeGranularities(...)` from `Task.detached` runs
truly on the background thread. Analytics skeleton → data in 1–3s without touching MainActor.

---

### Phase 2 — Transaction Windowing (Approach B)

Enable `windowMonths = 3` in `TransactionStore`. Reduces in-memory transactions from 19k → ~1–2k,
making all remaining O(N) operations 10–15× faster.

#### Blocker 1: BalanceCoordinator — use persisted balance

`Phase 28B` recalculates `shouldCalculateFromTransactions` account balances from full transaction
history. With a 3-month window this produces wrong results.

**Fix:** Trust the persisted `account.balance` field (already accurate — `persistIncremental`
updates it on every mutation). Remove Phase 28B recalculation from `AppCoordinator.initialize()`.
Keep Phase 28A (instant display from persisted value only).

**Files changed:**
- `Services/Balance/BalanceCoordinator.swift` — remove background recalculation from `registerAccounts(_:transactions:)`; `registerAccounts(_:)` becomes the only path
- `AppCoordinator.swift` — `initialize()` calls `registerAccounts(accounts)` only, no transaction parameter

#### Blocker 2: InsightsService — migrate generators to aggregate services

Four generators currently read raw `transactionStore.transactions` — they would silently
produce wrong data with a 3-month window.

| Generator | New data source |
|-----------|----------------|
| `accountDormancy` | `CategoryAggregateService` (last-transaction timestamp per account) |
| `spendingVelocity` | `MonthlyAggregateService` (monthly totals) |
| `incomeSourceBreakdown` | `CategoryAggregateService.fetchRange()` |
| `computePeriodDataPoints` (allTime/year) | `MonthlyAggregateService.fetchRange()` |

**Files changed:**
- `Services/Insights/InsightsService.swift` — replace raw-transaction reads in 4 generators with aggregate service reads; pass `categoryAggregateService` and `monthlyAggregateService` as dependencies

#### Blocker 3: Aggregate rebuild — bypass windowed store

`AppCoordinator.initialize()` rebuilds Phase 22 aggregates from `transactionStore.transactions`
(windowed). With a 3-month window, older months would be erased.

**Fix:** Rebuild path loads full history from repository directly:

```swift
Task.detached(priority: .background) {
    let allTx = repo.loadTransactions(dateRange: nil)  // full history, bypasses window
    await categoryAggregateService.rebuild(from: allTx, baseCurrency: currency)
    await monthlyAggregateService.rebuild(from: allTx, baseCurrency: currency)
}
```

**Files changed:**
- `AppCoordinator.swift` — update aggregate rebuild task to use `repo.loadTransactions(dateRange: nil)`
- `ViewModels/TransactionStore.swift` — set `windowMonths = 3`

---

## Expected Outcomes

| Metric | Before | After Phase 1 | After Phase 2 |
|--------|--------|--------------|--------------|
| Time to first frame | 2–4s | <100ms | <100ms |
| Skeleton → content | ~275ms block | non-blocking | non-blocking |
| Analytics first open | 1–3s block | non-blocking | non-blocking |
| In-memory transactions | 19k | 19k | ~1–2k |
| updateSummary() main thread | ~275ms | 0ms | 0ms |
| categoryExpenses() | ~50ms | ~50ms | ~3ms |

---

## Implementation Order

1. Fix A (CoreData pre-warm) — highest impact, lowest risk
2. Fix C (InsightsService de-isolation) — high impact, medium risk
3. Fix B (Summary off-thread) — medium impact, requires new SummaryCalculator
4. Phase 2, Blocker 3 (aggregate rebuild) — lowest risk blocker
5. Phase 2, Blocker 1 (BalanceCoordinator) — medium risk
6. Phase 2, Blocker 2 (InsightsService generators) — most work, requires testing

---

## Testing Checklist

- [ ] App first frame appears in <100ms on physical device
- [ ] Skeleton → account cards transition smooth (no jank)
- [ ] Skeleton → summary card transition smooth
- [ ] Analytics tab first open shows skeleton immediately, data appears without UI freeze
- [ ] Balances correct after windowing enabled (spot check 5 accounts)
- [ ] Insights data matches pre-windowing values for current month
- [ ] Historical insights (allTime, year) correct via aggregate services
- [ ] CSV import still works (triggers aggregate rebuild)
- [ ] Adding/deleting transactions updates balance correctly
- [ ] `PerformanceProfiler` shows no >100ms warnings in Console.app after launch
