# UI Freeze Elimination (Phase 31) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate three distinct UI freezes (launch, skeleton→content, analytics) and enable transaction windowing to reduce in-memory set from 19k to ~1-2k.

**Architecture:** Three targeted surgical fixes (Fix A/B/C) remove MainActor blocking without restructuring. Phase 2 enables the pre-existing `windowMonths` feature by resolving its three documented blockers.

**Tech Stack:** Swift 6 concurrency (`Task.detached`, `nonisolated`, `@MainActor`), CoreData, SwiftUI, `@Observable`, `NSLock` for thread-safe cache.

**Design doc:** `docs/plans/2026-02-24-ui-freeze-elimination-design.md`

---

## Implementation Order

1. **Task 1** — Fix A: CoreData pre-warm (highest impact, lowest risk)
2. **Task 2** — Fix C: InsightsService de-isolation (high impact, medium risk)
3. **Task 3** — Fix B: SummaryCalculator off-thread (medium impact, new file)
4. **Task 4** — Phase 2, Blocker 3: Aggregate rebuild from full history
5. **Task 5** — Phase 2, Blocker 1: Trust persisted balance, remove Phase B recalc
6. **Task 6** — Phase 2, Blocker 2: InsightsService generators → aggregate services
7. **Task 7** — Enable windowing: set `windowMonths = 3`

---

## Task 1: Fix A — CoreData Pre-Warm

**Problem:** `CoreDataStack.persistentContainer` is a `lazy var`. Its `loadPersistentStores()` call runs synchronously on MainActor inside `AppCoordinator.init()` when first touched via `CoreDataRepository()`. This blocks the render thread 2-4s before any frame appears.

**Fix:** Fire a `Task.detached` from AppDelegate to touch `persistentContainer` in the background before `AppCoordinator` is created. Make `AIFinanceManagerApp.coordinator` optional so the app shows a blank system background while the container warms.

**Files:**
- Modify: `AIFinanceManager/CoreData/CoreDataStack.swift`
- Modify: `AIFinanceManager/AppDelegate.swift`
- Modify: `AIFinanceManager/AIFinanceManagerApp.swift`

---

### Step 1: Add `preWarm()` to CoreDataStack

Open `AIFinanceManager/CoreData/CoreDataStack.swift`. After the `deinit` block (after line ~36), add this method in the `MARK: - Persistent Container` section, immediately before the `lazy var persistentContainer`:

```swift
// MARK: - Pre-Warm

/// Touch persistentContainer on a background thread so loadPersistentStores()
/// runs off MainActor. Call from AppDelegate.didFinishLaunchingWithOptions —
/// before AppCoordinator is created.
func preWarm() {
    Task.detached(priority: .userInitiated) {
        _ = CoreDataStack.shared.persistentContainer
    }
}
```

### Step 2: Call `preWarm()` as first line of AppDelegate

Open `AIFinanceManager/AppDelegate.swift`. Add `CoreDataStack.shared.preWarm()` as the very first statement inside `application(_:didFinishLaunchingWithOptions:)`, before everything else:

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    CoreDataStack.shared.preWarm()   // ← ADD THIS FIRST
    // Set notification delegate
    UNUserNotificationCenter.current().delegate = self
    // ... rest unchanged
```

### Step 3: Make coordinator optional in AIFinanceManagerApp

Open `AIFinanceManager/AIFinanceManagerApp.swift`. Replace the entire file content:

```swift
//
//  AIFinanceManagerApp.swift
//  AIFinanceManager
//
//  Created by Daulet Kydrali on 06.01.2026.
//
//  Phase 31: coordinator made optional — created only after CoreData pre-warm
//  completes so persistentContainer.loadPersistentStores() never blocks MainActor.
//

import SwiftUI

@main
struct AIFinanceManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var timeFilterManager = TimeFilterManager()
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
                    // System launch screen is still visible — show matching background
                    // so there is no flash when coordinator becomes ready.
                    Color(.systemBackground).ignoresSafeArea()
                }
            }
            .task {
                // Wait for CoreData pre-warm to finish (already started in AppDelegate).
                // If preWarm() finishes before this task runs, this await returns instantly.
                await Task.detached(priority: .userInitiated) {
                    _ = CoreDataStack.shared.persistentContainer
                }.value
                // Now safe to create AppCoordinator — persistentContainer is already open.
                coordinator = AppCoordinator()
            }
        }
    }
}
```

### Step 4: Build and verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no new errors.

### Step 5: Commit

```bash
git add \
  AIFinanceManager/CoreData/CoreDataStack.swift \
  AIFinanceManager/AppDelegate.swift \
  AIFinanceManager/AIFinanceManagerApp.swift
git commit -m "$(cat <<'EOF'
perf(launch): pre-warm CoreData on background thread before AppCoordinator init (Fix A)

Eliminates 2-4s launch freeze caused by lazy persistentContainer.loadPersistentStores()
blocking MainActor. Pre-warm fires from AppDelegate; coordinator made optional so first
frame appears in <100ms.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Fix C — InsightsService De-Isolation

**Problem:** `InsightsService` is declared `@MainActor final class`. When `InsightsViewModel.loadInsightsBackground()` calls `await service.computeGranularities(...)` inside a `Task.detached`, Swift automatically hops back to MainActor to execute the method. The entire 1-3s insight computation blocks the UI thread despite being inside a "background" task.

**Fix:** Remove `@MainActor` from the `InsightsService` class declaration. Make `InsightsCache` thread-safe by replacing its `@MainActor` isolation with an `NSLock` and `@unchecked Sendable`. Mark with explicit `@MainActor` any `InsightsService` methods that still need it (methods that directly read from `transactionStore`).

**Files:**
- Modify: `AIFinanceManager/Services/Insights/InsightsCache.swift`
- Modify: `AIFinanceManager/Services/Insights/InsightsService.swift`

---

### Step 1: De-isolate InsightsCache — replace @MainActor with NSLock

Open `AIFinanceManager/Services/Insights/InsightsCache.swift`. Replace the entire file:

```swift
//
//  InsightsCache.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  In-memory LRU cache with TTL for computed insights.
//
//  Phase 31: Removed @MainActor isolation. Protected by NSLock so the cache
//  can be read/written from InsightsService running on any thread.
//
//  Design:
//  - Maximum `capacity` entries (default 20) to bound memory usage
//  - TTL (default 5 min) expiry — stale entries are lazily removed on read
//  - LRU eviction: the access-ordered array `lruKeys` tracks usage order;
//    the oldest entry is evicted when capacity is exceeded
//  - All operations are O(1) via dictionary + O(n) LRU scan (n ≤ 20, negligible)
//

import Foundation

/// Thread-safe LRU insights cache. @unchecked Sendable — internal state protected by NSLock.
final class InsightsCache: @unchecked Sendable {
    // MARK: - Types

    private struct CacheEntry {
        let insights: [Insight]
        let timestamp: Date
    }

    // MARK: - Properties

    private var cache: [String: CacheEntry] = [:]
    /// Insertion-order list; most-recently used key moves to the back.
    private var lruKeys: [String] = []
    private let ttl: TimeInterval
    private let capacity: Int
    private let lock = NSLock()

    // MARK: - Init

    init(ttl: TimeInterval = 300, capacity: Int = 20) {
        self.ttl = ttl
        self.capacity = max(1, capacity)
    }

    // MARK: - Public API

    func get(key: String) -> [Insight]? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return nil }

        // TTL check — lazy eviction on read
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            evictLocked(key: key)
            return nil
        }

        // Promote to most-recently-used
        promoteLocked(key: key)
        return entry.insights
    }

    func set(key: String, insights: [Insight]) {
        lock.lock()
        defer { lock.unlock() }

        if cache[key] != nil {
            cache[key] = CacheEntry(insights: insights, timestamp: Date())
            promoteLocked(key: key)
        } else {
            if cache.count >= capacity, let oldest = lruKeys.first {
                evictLocked(key: oldest)
            }
            cache[key] = CacheEntry(insights: insights, timestamp: Date())
            lruKeys.append(key)
        }
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        lruKeys.removeAll()
    }

    func invalidate(category: InsightCategory) {
        lock.lock()
        defer { lock.unlock() }
        let keysToRemove = cache.keys.filter { $0.contains(category.rawValue) }
        for key in keysToRemove { evictLocked(key: key) }
    }

    // MARK: - Cache Key

    static func makeKey(timeFilter: TimeFilter, baseCurrency: String) -> String {
        "\(timeFilter.preset.rawValue)_\(baseCurrency)_\(timeFilter.startDate.timeIntervalSince1970)"
    }

    // MARK: - Private Helpers (call only while lock is held)

    private func promoteLocked(key: String) {
        if let idx = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: idx)
            lruKeys.append(key)
        }
    }

    private func evictLocked(key: String) {
        cache.removeValue(forKey: key)
        lruKeys.removeAll { $0 == key }
    }
}
```

### Step 2: Remove @MainActor from InsightsService class declaration

Open `AIFinanceManager/Services/Insights/InsightsService.swift`. Find line ~18-19:

```swift
@MainActor
final class InsightsService {
```

Change to:

```swift
final class InsightsService: @unchecked Sendable {
```

> **Why `@unchecked Sendable`?** InsightsService holds references to `@MainActor` services (transactionStore, budgetService). These are only accessed from explicitly `@MainActor`-annotated methods. The cache is now NSLock-protected. `@unchecked Sendable` tells Swift "I verified thread safety manually".

### Step 3: Check for any remaining @MainActor-required methods in InsightsService

After removing the class-level `@MainActor`, the Swift compiler will flag any method that accesses `@MainActor`-isolated state without being explicitly annotated. The most likely offender is `generateAllInsights(timeFilter:baseCurrency:)` — the first overload (lines ~72-120) which reads from `transactionStore` directly.

Search for all methods that directly access `transactionStore.transactions`, `transactionStore.accounts`, or `budgetService`:

```bash
grep -n "transactionStore\.\|budgetService\." \
  AIFinanceManager/Services/Insights/InsightsService.swift | head -30
```

Any method that accesses these `@MainActor`-isolated properties must be marked `@MainActor`. Add the annotation to those method signatures. The `computeGranularities(...)` and `generateAllInsights(granularity:transactions:...)` overloads — which accept pre-built arrays as parameters — do NOT need `@MainActor`.

### Step 4: Verify InsightsCache Sendable conformance compiles

Check `TransactionCacheManager` too — it's passed to `computeGranularities`:

```bash
grep -n "class TransactionCacheManager\|@MainActor\|Sendable" \
  AIFinanceManager/Services/Cache/TransactionCacheManager.swift | head -10
```

If `TransactionCacheManager` is `@MainActor` and not `Sendable`, add `@unchecked Sendable` to it as well (its cache dictionary is only written on MainActor anyway; background threads only read `getFilteredCache`/`getSummaryCache` which are also `@MainActor`, so the lock isn't needed there — just the conformance marker).

### Step 5: Build and fix any remaining compiler errors

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|warning:" | grep -v "$(pwd)/docs" | head -40
```

Fix any errors. Common patterns:
- `expression is 'async' but is not marked with 'await'` → the method now runs off MainActor, so calls to MainActor services need `await`
- `sending 'X' risks causing data races` → add `@unchecked Sendable` to the flagged class
- `actor-isolated ... cannot be referenced from a non-isolated context` → add `@MainActor` to that specific method in InsightsService

### Step 6: Commit

```bash
git add \
  AIFinanceManager/Services/Insights/InsightsCache.swift \
  AIFinanceManager/Services/Insights/InsightsService.swift
# Add any other files touched for Sendable conformance
git commit -m "$(cat <<'EOF'
perf(analytics): de-isolate InsightsService from @MainActor (Fix C)

Removes class-level @MainActor from InsightsService so computeGranularities()
executes truly on the background thread from Task.detached in InsightsViewModel.
InsightsCache gets NSLock protection and @unchecked Sendable conformance.
Eliminates 1-3s analytics tab freeze.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Fix B — SummaryCalculator Off-Thread

**Problem:** `ContentView.updateSummary()` calls filtering + `calculateSummary()` synchronously on MainActor (~275ms for 19k transactions). This blocks the render thread at the exact moment the skeleton lifts.

**Fix:** Extract summary computation into a new `nonisolated static func` in a new `SummaryCalculator` enum. Currency conversion is done directly from `tx.convertedAmount` (the same value `TransactionCurrencyService` caches), so no `@MainActor` service is needed. `ContentView.updateSummary()` dispatches via `Task.detached`.

**Files:**
- Create: `AIFinanceManager/Services/Transactions/SummaryCalculator.swift`
- Modify: `AIFinanceManager/Views/Home/ContentView.swift`

---

### Step 1: Create SummaryCalculator.swift

Create new file `AIFinanceManager/Services/Transactions/SummaryCalculator.swift`:

```swift
//
//  SummaryCalculator.swift
//  AIFinanceManager
//
//  Phase 31 Fix B: Pure off-thread summary computation.
//  Called from ContentView via Task.detached to keep MainActor free during
//  skeleton→content transition.
//

import Foundation

/// Pure, nonisolated summary calculator.
/// Accepts only value-type parameters so it can run on any thread.
/// Currency conversion mirrors TransactionCurrencyService.getConvertedAmountOrCompute:
/// uses tx.convertedAmount when available, falls back to tx.amount.
enum SummaryCalculator {

    nonisolated static func compute(
        transactions: [Transaction],
        filter: TimeFilter,
        currency: String
    ) -> Summary {
        let start  = filter.startDate
        let end    = filter.endDate
        let now    = Date()

        var totalIncome:    Double = 0
        var totalExpenses:  Double = 0
        var totalTransfers: Double = 0
        var plannedAmount:  Double = 0

        for tx in transactions {
            // Date range filter
            guard let txDate = DateFormatters.dateFormatter.date(from: tx.date) else { continue }
            guard txDate >= start && txDate <= end else { continue }

            // Currency conversion — mirrors TransactionCurrencyService logic
            let converted: Double
            if tx.currency == currency {
                converted = tx.amount
            } else {
                converted = tx.convertedAmount ?? tx.amount
            }

            switch tx.type {
            case .income:
                totalIncome += converted
            case .expense:
                if txDate > now {
                    plannedAmount += converted
                } else {
                    totalExpenses += converted
                }
            case .internalTransfer:
                totalTransfers += converted
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break   // Not included in home summary
            }
        }

        return Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalTransfers,
            netFlow: totalIncome - totalExpenses,
            currency: currency,
            startDate: start,
            endDate: end,
            plannedAmount: plannedAmount
        )
    }
}
```

> **Note on `DateFormatters`:** The project uses a `DateFormatters` utility enum/class with a static `dateFormatter`. Check where it is defined:
> ```bash
> grep -r "DateFormatters" AIFinanceManager/ --include="*.swift" -l
> ```
> If the formatter is `@MainActor`-isolated, use `ISO8601DateFormatter()` inline instead. If it is `nonisolated` or a plain static, use it as above.

### Step 2: Update ContentView.updateSummary() to use Task.detached

Open `AIFinanceManager/Views/Home/ContentView.swift`. Find the `updateSummary()` function. It currently looks something like:

```swift
private func updateSummary() {
    // ... synchronous filtering + calculateSummary() call ...
    cachedSummary = result
}
```

Replace the body with:

```swift
private func updateSummary() {
    let transactions = transactionStore.transactions   // copy on MainActor
    let filter       = timeFilterManager.currentFilter
    let currency     = viewModel.appSettings.baseCurrency

    summaryUpdateTask?.cancel()
    summaryUpdateTask = Task.detached(priority: .userInitiated) {
        let summary = SummaryCalculator.compute(
            transactions: Array(transactions),
            filter: filter,
            currency: currency
        )
        await MainActor.run { [weak viewModel] in
            // viewModel here is the ContentView's @Environment binding
            // Use the same property that was previously set synchronously
        }
    }
}
```

> **Important:** Look at the existing `updateSummary()` in `ContentView.swift` before editing. The property being set may be `cachedSummary` on a ViewModel or directly on ContentView. The `await MainActor.run` block should set that same property. Adapt the above template to match the actual property path.
>
> `summaryUpdateTask` was already added in Phase 30 (see ContentView.swift `@State private var summaryUpdateTask`). Do not add it again.

### Step 3: Build and verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:" | head -20
```

Expected: no errors. The `TransactionsSummaryCard` already shows `ProgressView()` when `cachedSummary == nil`, so no UI changes needed for loading state.

### Step 4: Commit

```bash
git add \
  AIFinanceManager/Services/Transactions/SummaryCalculator.swift \
  AIFinanceManager/Views/Home/ContentView.swift
git commit -m "$(cat <<'EOF'
perf(home): compute summary off MainActor with SummaryCalculator (Fix B)

Extracts nonisolated static compute() from TransactionQueryService logic.
ContentView.updateSummary() now dispatches via Task.detached — MainActor is
never blocked during the skeleton→content transition (~275ms eliminated).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Phase 2 Blocker 3 — Aggregate Rebuild from Full History

**Problem:** `AppCoordinator.initialize()` rebuilds Phase 22 aggregates from `transactionStore.transactions`. With windowing enabled, this is only the last 3 months — older months would be erased from `CategoryAggregateEntity` and `MonthlyAggregateEntity`.

**Fix:** Pass `dateRange: nil` to `repo.loadTransactions()` so the rebuild always uses full history, bypassing the window.

**Files:**
- Modify: `AIFinanceManager/ViewModels/AppCoordinator.swift`

---

### Step 1: Locate the aggregate rebuild task in AppCoordinator.initialize()

Open `AIFinanceManager/ViewModels/AppCoordinator.swift`. Find the `Task.detached(priority: .background)` block that calls `categoryAggregateService.rebuild` and `monthlyAggregateService.rebuild`. It currently reads:

```swift
Task.detached(priority: .background) {
    guard let self = self else { return }
    let txCount = await self.transactionStore.transactions.count
    let currency = await self.transactionStore.baseCurrency
    let allTx = await self.transactionStore.transactions   // ← windowed!
    // ...
    await self.transactionStore.categoryAggregateService.rebuild(from: allTx, baseCurrency: currency)
    await self.transactionStore.monthlyAggregateService.rebuild(from: allTx, baseCurrency: currency)
}
```

### Step 2: Replace windowed read with full-history load

Change the `allTx` capture to load directly from repository:

```swift
Task.detached(priority: .background) { [weak self] in
    guard let self else { return }
    let currency = await self.transactionStore.baseCurrency
    let repo     = await self.repository   // @ObservationIgnored let — safe to capture

    // Check if aggregates need rebuilding
    let existingMonthly = await self.transactionStore.monthlyAggregateService.fetchLast(
        1, currency: currency
    )
    let txCount = await self.transactionStore.transactions.count
    guard existingMonthly.first?.transactionCount == 0, txCount > 0 else { return }

    // Load FULL history — bypasses the in-memory window
    let allTx = repo.loadTransactions(dateRange: nil)

    await self.transactionStore.categoryAggregateService.rebuild(from: allTx, baseCurrency: currency)
    await self.transactionStore.monthlyAggregateService.rebuild(from: allTx, baseCurrency: currency)
}
```

> **Check `loadTransactions` signature:** Run:
> ```bash
> grep -n "func loadTransactions" AIFinanceManager/Services/Repository/*.swift \
>   AIFinanceManager/Services/Core/DataRepositoryProtocol.swift
> ```
> Confirm the parameter name is `dateRange:` and the method is `nonisolated` (callable from background). If it's `async`, add `await`. If it returns `[Transaction]`, use it directly. If it's `throws`, add `try?`.

### Step 3: Build and verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:" | head -20
```

### Step 4: Commit

```bash
git add AIFinanceManager/ViewModels/AppCoordinator.swift
git commit -m "$(cat <<'EOF'
perf(aggregates): rebuild from full transaction history not windowed store

Aggregate rebuild in AppCoordinator.initialize() now calls repo.loadTransactions(dateRange: nil)
so CategoryAggregateEntity and MonthlyAggregateEntity always reflect complete history,
not just the 3-month window.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Phase 2 Blocker 1 — Trust Persisted Balance

**Problem:** `BalanceCoordinator.registerAccounts(_:transactions:)` Phase B recalculates `shouldCalculateFromTransactions` accounts from the full transaction history. With a 3-month window, `transactionStore.transactions` won't contain full history, so Phase B would produce wrong balances. Phase B was a "safety verification pass" — but `account.balance` is already accurate because `persistIncremental` updates it synchronously on every mutation.

**Fix:** Remove Phase B from `registerAccounts`. `AppCoordinator.initialize()` calls `registerAccounts(accounts, transactions: transactionStore.transactions)` — change it to `registerAccounts(accounts)` (Phase A only).

**Files:**
- Modify: `AIFinanceManager/Services/Balance/BalanceCoordinator.swift`
- Modify: `AIFinanceManager/ViewModels/AppCoordinator.swift`

---

### Step 1: Remove Phase B recalculation from BalanceCoordinator

Open `AIFinanceManager/Services/Balance/BalanceCoordinator.swift`. Find the `registerAccounts` method. After the Phase A block (lines ~86-115 that set `self.balances`), delete everything from the `// ── Phase B` comment through the closing `}` of the `Task(priority: .utility)` block. The method should end right after:

```swift
        // Publish immediately — UI shows balances with zero startup delay.
        var merged = self.balances
        for (id, bal) in phase1Balances { merged[id] = bal }
        self.balances = merged
    }  // ← method ends here
```

Also update the method signature — `transactions` parameter is no longer needed. Change:

```swift
func registerAccounts(_ accounts: [Account], transactions: [Transaction] = []) async {
```

to:

```swift
func registerAccounts(_ accounts: [Account]) async {
```

If `BalanceCoordinatorProtocol` has this method, update the protocol signature too:

```bash
grep -n "registerAccounts" AIFinanceManager/Protocols/*.swift \
  AIFinanceManager/Services/Balance/BalanceCoordinator.swift
```

### Step 2: Update AppCoordinator.initialize() call site

Open `AIFinanceManager/ViewModels/AppCoordinator.swift`. Find the `registerAccounts` call in `initialize()` (currently passing `transactions: transactionStore.transactions`):

```swift
await balanceCoordinator.registerAccounts(
    transactionStore.accounts,
    transactions: transactionStore.transactions   // ← remove this
)
```

Change to:

```swift
await balanceCoordinator.registerAccounts(transactionStore.accounts)
```

### Step 3: Build and verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:" | head -20
```

Fix any call sites that still pass the `transactions:` label. Search:

```bash
grep -rn "registerAccounts" AIFinanceManager/ --include="*.swift"
```

### Step 4: Commit

```bash
git add \
  AIFinanceManager/Services/Balance/BalanceCoordinator.swift \
  AIFinanceManager/ViewModels/AppCoordinator.swift
git commit -m "$(cat <<'EOF'
perf(balance): remove Phase B recalculation from registerAccounts

Phase 28B recalculated shouldCalculateFromTransactions accounts from full
transaction history — unnecessary now that persistIncremental keeps account.balance
accurate on every mutation. Removes windowing blocker 1.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Phase 2 Blocker 2 — InsightsService Generators → Aggregate Services

**Problem:** Four insight generators in `InsightsService` read `transactionStore.transactions` directly. With windowing enabled, these would silently produce wrong data (only last 3 months of history).

**Generator → New data source mapping (from design doc):**

| Generator | Old source | New source |
|-----------|-----------|-----------|
| `accountDormancy` | raw transactions | `CategoryAggregateService` (last-tx timestamp per account) |
| `spendingVelocity` | raw transactions | `MonthlyAggregateService` (monthly totals) |
| `incomeSourceBreakdown` | raw transactions | `CategoryAggregateService.fetchRange()` |
| `computePeriodDataPoints` (allTime/year) | raw transactions | `MonthlyAggregateService.fetchRange()` |

**Files:**
- Modify: `AIFinanceManager/Services/Insights/InsightsService.swift`

---

### Step 1: Locate the four generators

```bash
grep -n "accountDormancy\|spendingVelocity\|incomeSourceBreakdown\|computePeriodDataPoints\|allTime\|year" \
  AIFinanceManager/Services/Insights/InsightsService.swift | head -30
```

### Step 2: Read the current generator implementations

For each of the four generators, read the 10-20 lines that currently iterate `allTransactions` to understand what they compute. You need to understand what summary they produce before you can replace the data source.

### Step 3: Check what aggregate services already expose

```bash
grep -n "func fetch\|func rebuild\|func fetchRange\|func fetchLast\|lastTransactionDate\|monthly" \
  AIFinanceManager/Services/Categories/CategoryAggregateService.swift \
  AIFinanceManager/Services/Balance/MonthlyAggregateService.swift | head -30
```

### Step 4: Update each generator

For each generator, replace the raw `allTransactions` scan with an aggregate service call. The general pattern:

**Before (accountDormancy example):**
```swift
// Scans all transactions O(N) to find last tx per account
let lastTxByAccount = Dictionary(grouping: allTransactions) { $0.accountId }
    .mapValues { $0.max(by: { $0.date < $1.date })?.date }
```

**After:**
```swift
// Read from CategoryAggregateService O(1) per account
let lastTxDates = categoryAggregateService.lastTransactionDates(for: accounts)
```

The exact replacement depends on what API the aggregate services expose. If the API doesn't exist yet, add the needed `func` to `CategoryAggregateService.swift` or `MonthlyAggregateService.swift` first (keep it minimal — only what the generator needs).

### Step 5: Verify generators pass categoryAggregateService and monthlyAggregateService

Check how `InsightsService` is initialized:

```bash
grep -n "InsightsService(" AIFinanceManager/ -r --include="*.swift"
```

If `categoryAggregateService` and `monthlyAggregateService` are not already injected, add them as initializer parameters and update the call site in `AppCoordinator`.

### Step 6: Build, run, and spot-check data

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:" | head -20
```

### Step 7: Commit

```bash
git add AIFinanceManager/Services/Insights/InsightsService.swift
# Add any service files with new aggregate methods
git commit -m "$(cat <<'EOF'
feat(insights): migrate 4 generators from raw transactions to aggregate services

accountDormancy, spendingVelocity, incomeSourceBreakdown, and computePeriodDataPoints
(allTime/year) now read from CategoryAggregateService / MonthlyAggregateService.
Removes windowing blocker 2 — these generators now produce correct data with windowed store.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Enable Transaction Windowing

**Problem:** `TransactionStore.windowMonths = 0` (disabled). All three blockers are now resolved.

**Fix:** Set `windowMonths = 3`. In-memory transactions drop from ~19k to ~1-2k; all O(N) operations become ~10-15× faster.

**Files:**
- Modify: `AIFinanceManager/ViewModels/TransactionStore.swift`

---

### Step 1: Change windowMonths to 3

Open `AIFinanceManager/ViewModels/TransactionStore.swift`. Find line ~180:

```swift
private let windowMonths: Int = 0  // disabled — see blockers above
```

Change to:

```swift
private let windowMonths: Int = 3
```

### Step 2: Build and verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:" | head -20
```

### Step 3: Run on simulator and spot-check

On simulator with test data (or the physical device):
- Open app → verify account balances are correct
- Check Analytics → verify current-month totals match pre-windowing values
- Add a new transaction → verify balance updates correctly
- Check Settings → verify historical insights (allTime, year) show correct data
- Run CSV import → verify triggers aggregate rebuild

### Step 4: Commit

```bash
git add AIFinanceManager/ViewModels/TransactionStore.swift
git commit -m "$(cat <<'EOF'
perf(store): enable transaction windowing (windowMonths = 3)

All three blockers resolved:
- Blocker 1: BalanceCoordinator trusts persisted account.balance
- Blocker 2: InsightsService generators read from aggregate services
- Blocker 3: Aggregate rebuild loads full history from repository

In-memory transaction count: ~19k → ~1-2k. All O(N) operations ~10-15x faster.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Testing Checklist

After all tasks are complete, verify against the design doc checklist:

```
- [ ] App first frame appears in <100ms on physical device (iPhone 17)
- [ ] Skeleton → account cards transition smooth (no jank)
- [ ] Skeleton → summary card transition smooth (no jank)
- [ ] Analytics tab first open shows skeleton immediately, data appears without UI freeze
- [ ] Balances correct after windowing enabled (spot check 5 accounts)
- [ ] Insights data matches pre-windowing values for current month
- [ ] Historical insights (allTime, year) correct via aggregate services
- [ ] CSV import still works (triggers aggregate rebuild)
- [ ] Adding/deleting transactions updates balance correctly
- [ ] PerformanceProfiler shows no >100ms warnings in Console.app after launch
```

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
