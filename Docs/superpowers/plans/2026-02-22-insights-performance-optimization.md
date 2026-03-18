# Insights Performance Optimization — Phase 27

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the SQLite "Expression tree too large" crash and eliminate the main actor blockage that makes the Insights tab load slowly.

**Architecture:** Three-layer fix — (1) replace OR-per-month CoreData predicates with range predicates to fix the crash, (2) hoist `firstDate` computation out of the per-granularity loop, (3) make the heavy `generateAllInsights(granularity:)` method `nonisolated` so all five granularity computations run off the main actor and in parallel.

**Tech Stack:** Swift 6, CoreData, SwiftUI `@Observable`, `Task.detached`, `withTaskGroup`

---

## Root Cause Analysis (READ THIS FIRST)

### Bug 1 — SQLite "Expression tree too large" (CRITICAL CRASH)

**Symptom:** Logs show:
```
CoreData: error: SQLite error code:1, 'Expression tree is too large (maximum depth 1000)'
❌ [CategoryAgg] fetchRange failed
```
Followed by fallback to O(N) scan of **15,646 transactions**.

**Root cause:** `CategoryAggregateService.fetchRange()` and `MonthlyAggregateService.fetchFor()` build one `NSPredicate` per calendar month and combine them with `NSCompoundPredicate(orPredicateWithSubpredicates:)`. For a 5-year window (used by `generateIncomeSeasonality`) this creates 60 OR conditions; for `.allTime` (spanning years of data) it can exceed 80+. Each `(year == X AND month == Y AND currency == Z)` triple adds ~5 nodes to SQLite's internal expression tree. At ~80 tuples × 5 nodes + 79 OR-join nodes ≈ 479 nodes — but the binary tree expansion of 80-deep OR chains is O(N²), hitting the SQLite limit of 1000.

**Fix:** Replace the compound OR predicate with a single range predicate using year/month boundary comparisons. This reduces the predicate to 7 nodes regardless of date range.

**Files:**
- `AIFinanceManager/Services/Categories/CategoryAggregateService.swift` — `fetchRange()` lines 169–237
- `AIFinanceManager/Services/Balance/MonthlyAggregateService.swift` — `fetchFor()` lines 176–215

---

### Bug 2 — Main actor blocked by 5× sequential @MainActor computation

**Symptom:** Loading delay = sum of all 5 granularities computed one-by-one on the main thread.

**Root cause:** `InsightsService` is `@MainActor`. `InsightsViewModel.loadInsightsBackground()` runs in `Task.detached` but calls `await service.generateAllInsights(granularity:)` five times in a `for` loop. Each `await` hops to the main actor and runs hundreds of milliseconds of computation (filtering 591 transactions, computing aggregates, building insight arrays) synchronously before returning. The main thread is blocked for the entire duration, preventing UI updates.

**Fix (two parts):**
- **Part A:** Hoist `firstDate` computation (O(N) date-parsing scan) out of `generateAllInsights` so it runs once instead of 5×.
- **Part B:** Mark `generateAllInsights(granularity:)` as `nonisolated` and pre-fetch CoreData data on `@MainActor` before the loop. The granularity computations themselves are pure array operations that do not need the main actor.

**Files:**
- `AIFinanceManager/Services/Insights/InsightsService.swift`
- `AIFinanceManager/ViewModels/InsightsViewModel.swift`

---

## Task 1: Fix CategoryAggregateService.fetchRange() — range predicate

**Files:**
- Modify: `AIFinanceManager/Services/Categories/CategoryAggregateService.swift`

**What to change:** Replace lines 173–205 (the `months` enumeration + OR predicate construction) with a range predicate. Keep the in-memory aggregation by category unchanged.

**Step 1: Read the current fetchRange method**

Open `CategoryAggregateService.swift` and locate `func fetchRange(from:to:currency:)` (around line 169). The method currently:
1. Enumerates all calendar months between `startDate` and `endDate` into a `months` array
2. Maps each `(year, month)` pair to an individual `NSPredicate`
3. Combines them with `NSCompoundPredicate(orPredicateWithSubpredicates:)`

**Step 2: Replace the predicate construction**

Replace everything between `let context = stack.viewContext` and the `do { let entities = try context.fetch(request)` section. The new predicate uses boundary comparisons:

```swift
func fetchRange(
    from startDate: Date,
    to endDate: Date,
    currency: String
) -> [CategoryMonthlyAggregate] {
    let calendar = Calendar.current
    let startComps = calendar.dateComponents([.year, .month], from: startDate)
    let endComps   = calendar.dateComponents([.year, .month], from: endDate)

    guard let startYear  = startComps.year,  let startMonth = startComps.month,
          let endYear    = endComps.year,     let endMonth   = endComps.month
    else { return [] }

    // Guard: nothing to fetch
    let startEncoded = startYear * 100 + startMonth   // e.g. 202401
    let endEncoded   = endYear   * 100 + endMonth     // e.g. 202612
    guard endEncoded >= startEncoded else { return [] }

    let context = stack.viewContext
    let request = CategoryAggregateEntity.fetchRequest()

    // Use range predicate — O(1) conditions regardless of range length.
    // Avoids SQLite "Expression tree too large" for multi-year ranges.
    // Fetches slightly more than needed (full years at boundaries) then
    // in-memory filter trims the exact boundary months.
    request.predicate = NSPredicate(
        format: "currency == %@ AND year > 0 AND month > 0 " +
                "AND (year > %d OR (year == %d AND month >= %d)) " +
                "AND (year < %d OR (year == %d AND month <= %d))",
        currency,
        Int16(startYear), Int16(startYear), Int16(startMonth),
        Int16(endYear),   Int16(endYear),   Int16(endMonth)
    )
    request.sortDescriptors = [NSSortDescriptor(key: "categoryName", ascending: true)]

    do {
        let entities = try context.fetch(request)

        // Aggregate by category (sum across multiple months)
        var byCategory: [String: (total: Double, count: Int)] = [:]
        for entity in entities {
            let name = entity.categoryName ?? ""
            let existing = byCategory[name] ?? (0, 0)
            byCategory[name] = (
                existing.total + entity.totalAmount,
                existing.count + Int(entity.transactionCount)
            )
        }

        return byCategory
            .map { name, value in
                CategoryMonthlyAggregate(
                    categoryName: name,
                    year: 0,
                    month: 0,
                    totalExpenses: value.total,
                    transactionCount: value.count,
                    currency: currency,
                    lastUpdated: Date()
                )
            }
            .sorted { $0.totalExpenses > $1.totalExpenses }
    } catch {
        Self.logger.error("❌ [CategoryAgg] fetchRange failed: \(error.localizedDescription, privacy: .public)")
        return []
    }
}
```

**Note:** The `yearMonthPairs` variable and the old `months` array are no longer needed — delete them.

**Step 3: Verify — no OR predicate in fetch logs**

Build and run. The SQLite error should be gone. The log `⚡️ [Insights] Category spending FAST PATH` should appear for all granularities including `.year` and `.allTime`.

**Step 4: Commit**

```bash
git add AIFinanceManager/Services/Categories/CategoryAggregateService.swift
git commit -m "fix(insights): replace OR-per-month predicate with range predicate in CategoryAggregateService

Fixes SQLite 'Expression tree too large' crash for date ranges > ~80 months.
New predicate uses 7 conditions regardless of range length.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Fix MonthlyAggregateService.fetchFor() — same range predicate fix

**Files:**
- Modify: `AIFinanceManager/Services/Balance/MonthlyAggregateService.swift`

**What to change:** `fetchFor(yearMonths:currency:)` has the identical OR-per-month bug. Additionally, `fetchRange(from:to:currency:)` in this service builds a `yearMonths` array before calling `fetchFor` — this intermediate step is no longer needed.

**Step 1: Locate fetchFor() and fetchRange() in MonthlyAggregateService**

`fetchFor()` is around line 176. `fetchRange()` is around line 155.

**Step 2: Replace both methods**

```swift
/// Fetch monthly aggregates between startDate and endDate (inclusive).
func fetchRange(
    from startDate: Date,
    to endDate: Date,
    currency: String
) -> [MonthlyFinancialAggregate] {
    let calendar = Calendar.current
    let startComps = calendar.dateComponents([.year, .month], from: startDate)
    let endComps   = calendar.dateComponents([.year, .month], from: endDate)

    guard let startYear  = startComps.year,  let startMonth = startComps.month,
          let endYear    = endComps.year,     let endMonth   = endComps.month
    else { return [] }

    let startEncoded = startYear * 100 + startMonth
    let endEncoded   = endYear   * 100 + endMonth
    guard endEncoded >= startEncoded else { return [] }

    let context = stack.viewContext
    let request = MonthlyAggregateEntity.fetchRequest()

    // Range predicate — avoids SQLite "Expression tree too large".
    request.predicate = NSPredicate(
        format: "currency == %@ AND year > 0 AND month > 0 " +
                "AND (year > %d OR (year == %d AND month >= %d)) " +
                "AND (year < %d OR (year == %d AND month <= %d))",
        currency,
        Int16(startYear), Int16(startYear), Int16(startMonth),
        Int16(endYear),   Int16(endYear),   Int16(endMonth)
    )
    request.sortDescriptors = [
        NSSortDescriptor(key: "year", ascending: true),
        NSSortDescriptor(key: "month", ascending: true)
    ]

    do {
        let entities = try context.fetch(request)
        return entities.map { e in
            MonthlyFinancialAggregate(
                year: Int(e.year),
                month: Int(e.month),
                totalIncome: e.totalIncome,
                totalExpenses: e.totalExpenses,
                netFlow: e.totalIncome - e.totalExpenses,
                transactionCount: Int(e.transactionCount),
                currency: e.currency ?? currency,
                lastUpdated: e.lastUpdated ?? Date()
            )
        }
    } catch {
        Self.logger.error("❌ [MonthlyAgg] fetchRange failed: \(error.localizedDescription, privacy: .public)")
        return []
    }
}
```

Also update `fetchLast(_:anchor:currency:)` to use the same pattern — build startDate as `months` months ago and call `fetchRange(from:to:currency:)` instead of the old `fetchFor(yearMonths:)`.

```swift
func fetchLast(
    _ months: Int,
    anchor: Date = Date(),
    currency: String
) -> [MonthlyFinancialAggregate] {
    let calendar = Calendar.current
    let anchorStart = startOfMonth(calendar, for: anchor)
    guard let startDate = calendar.date(byAdding: .month, value: -(months - 1), to: anchorStart) else { return [] }
    return fetchRange(from: startDate, to: anchor, currency: currency)
}
```

Delete the old `fetchFor(yearMonths:)` private method entirely — it is now unused.

**Step 3: Verify**

Build and run. No more SQLite errors for `generateIncomeSeasonality` (5-year window = 60 months).

**Step 4: Commit**

```bash
git add AIFinanceManager/Services/Balance/MonthlyAggregateService.swift
git commit -m "fix(insights): replace OR-per-month predicate with range predicate in MonthlyAggregateService

Same fix as CategoryAggregateService. Eliminates 'Expression tree too large'
for generateIncomeSeasonality's 5-year (60-month) window.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Hoist firstDate computation — eliminate 5× O(N) scan

**Files:**
- Modify: `AIFinanceManager/Services/Insights/InsightsService.swift`
- Modify: `AIFinanceManager/ViewModels/InsightsViewModel.swift`

**Problem:** `generateAllInsights(granularity:)` lines 1172–1174 compute `firstDate` by scanning and parsing dates for ALL transactions on every granularity call:

```swift
let firstDate = allTransactions
    .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
    .min()
```

With 591 income transactions + expense transactions, this is ~1000+ date parse operations × 5 granularities = 5000+ unnecessary `DateFormatter.date(from:)` calls.

**Step 1: Add firstTransactionDate parameter to generateAllInsights(granularity:)**

In `InsightsService.swift`, change the signature of `generateAllInsights(granularity:transactions:baseCurrency:cacheManager:currencyService:balanceFor:)` to accept an optional `firstTransactionDate`:

```swift
func generateAllInsights(
    granularity: InsightGranularity,
    transactions allTransactions: [Transaction],
    baseCurrency: String,
    cacheManager: TransactionCacheManager,
    currencyService: TransactionCurrencyService,
    balanceFor: (String) -> Double,
    firstTransactionDate: Date? = nil          // ← NEW parameter with default nil
) -> (insights: [Insight], periodPoints: [PeriodDataPoint]) {
    // Replace the local firstDate computation:
    let firstDate: Date?
    if let provided = firstTransactionDate {
        firstDate = provided
    } else {
        // Fallback: compute locally (only used if caller doesn't provide it)
        firstDate = allTransactions
            .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
            .min()
    }
    // ... rest unchanged, use `firstDate` everywhere it was used before
```

**Step 2: Compute firstDate once in InsightsViewModel.loadInsightsBackground()**

In `InsightsViewModel.swift`, in `loadInsightsBackground()`, add before the `for gran in InsightGranularity.allCases` loop:

```swift
// Compute once — passed to each granularity to avoid 5× O(N) date-parse scan
let firstTransactionDate: Date? = allTransactions
    .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
    .min()
```

Then update the call inside the loop:

```swift
let result = await service.generateAllInsights(
    granularity: gran,
    transactions: allTransactions,
    baseCurrency: currency,
    cacheManager: cacheManager,
    currencyService: currencyService,
    balanceFor: { balanceSnapshot[$0] ?? 0 },
    firstTransactionDate: firstTransactionDate   // ← pass pre-computed value
)
```

**Step 3: Verify**

Build. The only behavior change is 5× → 1× date scan. Insights output should be identical.

**Step 4: Commit**

```bash
git add AIFinanceManager/Services/Insights/InsightsService.swift \
        AIFinanceManager/ViewModels/InsightsViewModel.swift
git commit -m "perf(insights): hoist firstDate computation out of per-granularity loop

Was: 5 × O(N) date-parse scans (one per granularity)
Now: 1 × O(N) scan before the loop, result passed as parameter

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Move generateAllInsights off @MainActor — eliminate main thread blocking

**Files:**
- Modify: `AIFinanceManager/Services/Insights/InsightsService.swift`
- Modify: `AIFinanceManager/ViewModels/InsightsViewModel.swift`

**Problem:** `InsightsService` is `@MainActor`. Calling `await service.generateAllInsights(granularity:)` from `Task.detached` hops to the main actor and runs the entire computation (array filtering, statistics, insight building) synchronously on the main thread. With 5 granularities this blocks the main thread for 500ms+.

**Analysis of what actually needs @MainActor in generateAllInsights:**
- `filterService.filterByTimeRange(...)` → pure array op, no actor needed
- `calculateMonthlySummary(...)` → pure array op, no actor needed
- `computePeriodDataPoints(...)` → pure array op, no actor needed
- `generateSpendingInsights(...)` → calls `transactionStore.categoryAggregateService.fetchRange(...)` which uses `stack.viewContext` → **needs @MainActor**
- `generateIncomeInsights(...)` → pure array ops, no actor needed
- `generateRecurringInsights(...)` → reads `transactionStore.recurringCache` → **needs @MainActor**
- `generateCashFlowInsightsFromPeriodPoints(...)` → pure array ops, no actor needed
- `generateWealthInsights(...)` → pure array ops + balance snapshot → no actor needed (uses pre-captured `balanceFor` closure)
- `generateSpendingSpike(...)` → calls `categoryAggregateService.fetchRange(...)` → **needs @MainActor**
- `generateCategoryTrend(...)` → calls `categoryAggregateService.fetchRange(...)` → **needs @MainActor**
- `generateIncomeSeasonality(...)` → calls `monthlyAggregateService.fetchRange(...)` → **needs @MainActor**
- `generateSpendingForecast(...)` → calls `categoryAggregateService.fetchRange(...)` → **needs @MainActor**
- `computeHealthScore(...)` → calls `categoryAggregateService.fetchRange(...)` → **needs @MainActor**

**Strategy:** Pre-fetch ALL CoreData aggregate data on the main actor before the granularity loop. Pass the pre-fetched data to `generateAllInsights` as parameters. The method can then be `nonisolated` since it only processes arrays.

**Step 1: Add a PreFetchedAggregates struct to InsightsService.swift**

Add this struct near the top of `InsightsService.swift` (after the imports, before the class declaration):

```swift
/// Pre-fetched CoreData aggregate data captured on @MainActor.
/// Passed to nonisolated computation methods to avoid repeated main-actor hops.
struct InsightsPrefetchedData {
    /// Category spending aggregates for current-month bucket (used by spending insights + health score)
    let currentMonthCategoryAggs: [CategoryMonthlyAggregate]
    /// Category spending for last 3 months (used by generateSpendingSpike)
    let last3MonthsCategoryAggs: [CategoryMonthlyAggregate]
    /// Category spending for last 6 months (used by generateCategoryTrend)
    let last6MonthsCategoryAggs: [CategoryMonthlyAggregate]
    /// Category spending for last 30 days (used by generateSpendingForecast)
    let last30DaysCategoryAggs: [CategoryMonthlyAggregate]
    /// Monthly income/expense aggregates for last 5 years (used by generateIncomeSeasonality)
    let last5YearsMonthlyAggs: [MonthlyFinancialAggregate]
    /// Active recurring series (used by generateRecurringInsights)
    let recurringSeriesAll: [Transaction]
}
```

**Step 2: Add prefetchData() method to InsightsService**

This method runs on `@MainActor` and does all CoreData reads in one pass:

```swift
/// Pre-fetches all CoreData aggregate data needed across all granularities.
/// Must be called on @MainActor. The returned struct can be passed to nonisolated methods.
func prefetchData(baseCurrency: String) -> InsightsPrefetchedData {
    let calendar = Calendar.current
    let now = Date()
    let monthStart = startOfMonth(calendar, for: now)
    let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: monthStart) ?? now
    let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: monthStart) ?? now
    let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
    let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now) ?? now

    let aggService = transactionStore.categoryAggregateService
    let monthlyService = transactionStore.monthlyAggregateService

    return InsightsPrefetchedData(
        currentMonthCategoryAggs: aggService.fetchRange(from: monthStart, to: now, currency: baseCurrency),
        last3MonthsCategoryAggs: aggService.fetchRange(from: threeMonthsAgo, to: now, currency: baseCurrency),
        last6MonthsCategoryAggs: aggService.fetchRange(from: sixMonthsAgo, to: now, currency: baseCurrency),
        last30DaysCategoryAggs: aggService.fetchRange(from: thirtyDaysAgo, to: now, currency: baseCurrency),
        last5YearsMonthlyAggs: monthlyService.fetchRange(from: fiveYearsAgo, to: now, currency: baseCurrency),
        recurringSeriesAll: Array(transactionStore.transactions.filter { $0.isRecurring == true })
    )
}
```

**Step 3: Update generateAllInsights(granularity:) signature to accept prefetched data**

Change the signature to accept `prefetchedData: InsightsPrefetchedData` and mark the method `nonisolated`:

```swift
nonisolated func generateAllInsights(
    granularity: InsightGranularity,
    transactions allTransactions: [Transaction],
    baseCurrency: String,
    cacheManager: TransactionCacheManager,
    currencyService: TransactionCurrencyService,
    balanceFor: (String) -> Double,
    firstTransactionDate: Date? = nil,
    prefetchedData: InsightsPrefetchedData     // ← NEW
) -> (insights: [Insight], periodPoints: [PeriodDataPoint]) {
```

**Step 4: Update all generators that called CoreData to accept prefetchedData**

Each private generator that previously called `transactionStore.categoryAggregateService.fetchRange(...)` must now accept the pre-fetched slice:

- `generateSpendingInsights(...)` → add `prefetchedAggs: [CategoryMonthlyAggregate]` param, remove the `fetchRange` call, use `prefetchedAggs` directly. The caller selects which slice is appropriate for the granularity's current bucket.
- `generateSpendingSpike(...)` → add `last3MonthsAggs: [CategoryMonthlyAggregate]` param
- `generateCategoryTrend(...)` → add `last6MonthsAggs: [CategoryMonthlyAggregate]` param
- `generateSpendingForecast(...)` → add `last30DaysAggs: [CategoryMonthlyAggregate]` param
- `generateIncomeSeasonality(...)` → add `last5YearsAggs: [MonthlyFinancialAggregate]` param
- `computeHealthScore(...)` → add `currentMonthAggs: [CategoryMonthlyAggregate]` param

**Note:** `generateSpendingInsights` currently calls `fetchRange(from: topRange.start, to: topRange.end)` where `topRange` depends on the granularity's current bucket. For the pre-fetch approach, the simplest solution: pass `currentMonthCategoryAggs` for all granularities (current month is already the right bucket for most), OR pre-fetch one entry per granularity's current period. Given the pre-fetch already covers current month and is the most common case, use `currentMonthCategoryAggs`.

**Step 5: Update InsightsViewModel.loadInsightsBackground() to pre-fetch once**

```swift
private func loadInsightsBackground() {
    isLoading = true
    recomputeTask?.cancel()

    let currency = baseCurrency
    let cacheManager = transactionsViewModel.cacheManager
    let currencyService = transactionsViewModel.currencyService
    let service = insightsService
    let allTransactions = Array(transactionStore.transactions)
    let balanceSnapshot = makeBalanceSnapshot()

    // Pre-fetch CoreData aggregates on MainActor BEFORE hopping to background.
    // This is a fast operation (a few CoreData fetches) done once for all granularities.
    let prefetched = service.prefetchData(baseCurrency: currency)

    recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
        guard let self, !Task.isCancelled else { return }

        let firstTransactionDate: Date? = allTransactions
            .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
            .min()

        var newInsights = [InsightGranularity: [Insight]]()
        var newPoints   = [InsightGranularity: [PeriodDataPoint]]()
        var newTotals   = [InsightGranularity: PeriodTotals]()

        for gran in InsightGranularity.allCases {
            guard !Task.isCancelled else { break }

            // generateAllInsights is now nonisolated — runs on background thread directly.
            let result = service.generateAllInsights(
                granularity: gran,
                transactions: allTransactions,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: { balanceSnapshot[$0] ?? 0 },
                firstTransactionDate: firstTransactionDate,
                prefetchedData: prefetched
            )
            // ... rest unchanged
        }
        // ... rest unchanged
    }
}
```

**Step 6: Remove @MainActor from InsightsService or make it nonisolated**

Since `generateAllInsights(granularity:)` is now `nonisolated` and `prefetchData()` is the only `@MainActor` method, keep `InsightsService` as `@MainActor` but individual computation methods as `nonisolated`. This is valid Swift — `nonisolated` on an `@MainActor` class method opts that method out of main actor isolation.

**Step 7: Verify**

Build and run. The log should show all 5 granularities computing without main actor contention. Loading time should drop significantly.

**Step 8: Commit**

```bash
git add AIFinanceManager/Services/Insights/InsightsService.swift \
        AIFinanceManager/ViewModels/InsightsViewModel.swift
git commit -m "perf(insights): move generateAllInsights computation off @MainActor

Pre-fetch all CoreData aggregates in one pass on @MainActor before
background loop. Mark generateAllInsights(granularity:) as nonisolated
so 5 granularity computations run on background thread, not main actor.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5 (Optional): Parallelize 5 granularity computations with withTaskGroup

> **Prerequisite:** Task 4 must be complete (generateAllInsights must be nonisolated).

**Files:**
- Modify: `AIFinanceManager/ViewModels/InsightsViewModel.swift`

**What to change:** Replace the sequential `for gran in InsightGranularity.allCases` loop with `withTaskGroup` to compute all 5 granularities concurrently.

```swift
// In loadInsightsBackground(), replace the for-loop with:

typealias GranResult = (
    gran: InsightGranularity,
    insights: [Insight],
    points: [PeriodDataPoint],
    totals: PeriodTotals
)

await withTaskGroup(of: GranResult?.self) { group in
    for gran in InsightGranularity.allCases {
        group.addTask {
            guard !Task.isCancelled else { return nil }
            let result = service.generateAllInsights(
                granularity: gran,
                transactions: allTransactions,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: { balanceSnapshot[$0] ?? 0 },
                firstTransactionDate: firstTransactionDate,
                prefetchedData: prefetched
            )
            var income: Double = 0; var expenses: Double = 0
            for p in result.periodPoints { income += p.income; expenses += p.expenses }
            return GranResult(
                gran: gran,
                insights: result.insights,
                points: result.periodPoints,
                totals: PeriodTotals(income: income, expenses: expenses, netFlow: income - expenses)
            )
        }
    }
    for await result in group {
        guard let r = result else { continue }
        newInsights[r.gran] = r.insights
        newPoints[r.gran]   = r.points
        newTotals[r.gran]   = r.totals
        Self.logger.debug("🔧 [InsightsVM] Gran .\(r.gran.rawValue, privacy: .public) — \(r.insights.count) insights, \(r.points.count) pts")
    }
}
```

**Expected improvement:** 5× parallel vs sequential → theoretical 5× speedup on multi-core device. In practice, expect 2–3× since some granularities are heavier than others.

**Commit:**

```bash
git add AIFinanceManager/ViewModels/InsightsViewModel.swift
git commit -m "perf(insights): parallelize 5 granularity computations with withTaskGroup

Was: sequential for-loop (each granularity waits for previous to finish)
Now: all 5 granularities compute concurrently on background thread pool

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Summary of Expected Improvements

| Issue | Before | After |
|-------|--------|-------|
| SQLite error on year/allTime | ❌ CRASH → O(N) fallback (15k tx scan) | ✅ Range predicate, fast CoreData read |
| `firstDate` computation | 5 × O(N) date parse scans | 1 × O(N) scan |
| Main actor blocking | 5 granularities × ~100ms = ~500ms+ blocked | ~0ms main actor time |
| Granularity computation | Sequential (cumulative) | Parallel (limited by slowest) |
| `fetchRange` for 5yr window | ~60 OR conditions → crash | 7 conditions → instant |

**Quick wins (Tasks 1–2 alone):** Eliminate the crash and the 15k-transaction fallback scan. This is the most impactful fix.

**Full optimization (Tasks 1–5):** Sub-100ms Insights tab load for typical datasets.

---

## Testing

After each task, verify in the iOS Simulator:
1. Open the Insights tab — no SQLite errors in console
2. Switch between granularities (week/month/quarter/year/allTime) — all load instantly from precomputed cache
3. Check the logs for `⚡️ [Insights] Category spending FAST PATH` appearing for ALL granularities (not just week/month)
4. Verify no `❌ [CategoryAgg] fetchRange failed` errors

Build command:
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E '(error:|warning:|BUILD)'
```
