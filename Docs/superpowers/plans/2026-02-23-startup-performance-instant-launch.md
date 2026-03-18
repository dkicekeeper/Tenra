# Phase 28: Instant Launch — Startup Performance Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate the startup spinner for 19k transactions — UI appears instantly, data fills in from background.

**Architecture:** Seven targeted fixes across four layers: progressive UI (ContentView), background CoreData fetch (TransactionStore/Repository), two-phase balance registration (BalanceCoordinator), and incremental O(1) persist per mutation (TransactionRepository). Each task is independent and safe to commit separately.

**Tech Stack:** SwiftUI @Observable, CoreData NSBatchInsertRequest (iOS 14+), Swift async/await background context (`context.perform { }`), UserDefaults, `@MainActor`

**Severity legend:** 🔴 blocks UI thread · 🟡 unnecessary work · 🟢 safe/background

---

## Root Cause Map

| # | Symptom | Root Cause | Fix |
|---|---------|------------|-----|
| 1 | Startup blocks for seconds | `loadData()` faults 19k CoreData entities on `viewContext` (main thread) | Task 3 |
| 2 | User sees blank spinner | `ContentView.initializeIfNeeded` shows overlay until ALL steps done | Task 2 |
| 3 | Every mutation = 57k CoreData ops | `saveTransactions([19k])` — fetches entire table, diffs, saves | Task 5+6 |
| 4 | Slow for `shouldCalculateFromTransactions` accounts | `registerAccounts` iterates 19k txs × N accounts on startup | Task 4 |
| 5 | Extra sequential work at startup | `generateRecurringTransactions` runs before UI is shown | Task 1 |
| 6 | CSV import slow + full rebuild | `bulkAdded` triggers `saveTransactions([full set])` | Task 7 |

---

## Task 1: Defer `generateRecurringTransactions` to post-load background

**Time:** ~5 min
**Risk:** 🟢 Low — no data model changes
**Impact:** Removes one blocking step from startup critical path

**Files:**
- Modify: `AIFinanceManager/ViewModels/AppCoordinator.swift:232`

**Step 1: Remove the blocking call from `initialize()`**

In `AppCoordinator.initialize()`, find and remove:
```swift
// 4. Generate recurring transactions (needs loaded data)
transactionsViewModel.generateRecurringTransactions()
```

**Step 2: Add background task right after balanceCoordinator step**

Replace the removed line with:
```swift
// 4. Generate recurring transactions in background (non-blocking)
Task.detached(priority: .background) { [weak self] in
    guard let self else { return }
    await MainActor.run {
        self.transactionsViewModel.generateRecurringTransactions()
    }
}
```

**Step 3: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|warning:|BUILD"
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add AIFinanceManager/ViewModels/AppCoordinator.swift
git commit -m "perf(startup): defer generateRecurringTransactions to background task (Phase 28-F)"
```

---

## Task 2: Progressive UI — show home screen immediately

**Time:** ~20 min
**Risk:** 🟢 Low — only affects loading overlay visibility
**Impact:** User sees the app UI in <100ms regardless of data load time

**Files:**
- Modify: `AIFinanceManager/Views/Home/ContentView.swift`

**Step 1: Understand current blocking pattern**

```swift
// CURRENT (blocks): isInitializing = true → spinner shown → all steps done → isInitializing = false
private func initializeIfNeeded() async {
    guard isInitializing else { return }
    await coordinator.initialize()          // blocks until ALL 5 steps done
    withAnimation { isInitializing = false }
}
```

**Step 2: Split initialize into fast-path + full-load**

In `AppCoordinator.swift`, add a fast-path init above `initialize()`:

```swift
/// Fast-path startup: loads only accounts and settings (< 50ms).
/// Called immediately so UI can appear. Full data arrives via initialize().
func initializeFastPath() async {
    guard !isInitialized else { return }
    // Load only accounts (small dataset, needed for home screen cards)
    try? await transactionStore.loadAccountsOnly()
    // Settings (UserDefaults read — instant)
    await settingsViewModel.loadInitialData()
}
```

In `TransactionStore.swift`, add `loadAccountsOnly()`:

```swift
/// Lightweight startup load: only accounts + categories.
/// Transactions are loaded fully by loadData() called afterwards.
func loadAccountsOnly() async throws {
    let bgContext = CoreDataStack.shared.newBackgroundContext()
    let (accs, cats) = try await bgContext.perform {
        let accs = try bgContext.fetch(AccountEntity.fetchRequest()).map { $0.toAccount() }
        let cats = try bgContext.fetch(CustomCategoryEntity.fetchRequest()).map { $0.toCustomCategory() }
        return (accs, cats)
    }
    accounts = AccountOrderManager.shared.applyOrders(to: accs)
    categories = CategoryOrderManager.shared.applyOrders(to: cats)
}
```

**Step 3: Make ContentView non-blocking**

Replace `initializeIfNeeded()` in `ContentView.swift`:

```swift
// BEFORE:
private func initializeIfNeeded() async {
    guard isInitializing else { return }
    await coordinator.initialize()
    withAnimation { isInitializing = false }
}

// AFTER:
private func initializeIfNeeded() async {
    guard isInitializing else { return }
    // Fast path: show UI with account cards immediately
    await coordinator.initializeFastPath()
    withAnimation(.easeOut(duration: 0.2)) { isInitializing = false }
    // Full load continues in background — @Observable updates UI when ready
    await coordinator.initialize()
}
```

**Step 4: Lighten the loading overlay**

Change the loading overlay in `ContentView.swift` to a subtler skeleton instead of a full-screen block:

```swift
// BEFORE: entire content hidden (opacity 0) behind overlay
.opacity(isInitializing ? 0 : 1)

// AFTER: content visible immediately; overlay only covers accounts carousel during fast-path
// (Remove the .opacity modifier from mainContent entirely)
```

In `loadingOverlay`, change the full-screen overlay to a small top banner:
```swift
@ViewBuilder
private var loadingOverlay: some View {
    if isInitializing {
        VStack {
            HStack(spacing: AppSpacing.sm) {
                ProgressView().scaleEffect(0.8)
                Text(String(localized: "progress.loadingData", defaultValue: "Loading..."))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, AppSpacing.sm)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
```

**Step 5: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add AIFinanceManager/ViewModels/AppCoordinator.swift \
        AIFinanceManager/ViewModels/TransactionStore.swift \
        AIFinanceManager/Views/Home/ContentView.swift
git commit -m "perf(startup): progressive UI — show home screen instantly via fast-path init (Phase 28-A)"
```

---

## Task 3: Background CoreData fetch in `loadData()` 🔴 CRITICAL

**Time:** ~40 min
**Risk:** 🟡 Medium — changes CoreData context used for read
**Impact:** Largest single win — moves `entities.map { $0.toTransaction() }` for 19k records off main thread. Expected 3-5× startup speedup.

**Root cause detail:**
```
// CURRENT: ALL on main thread (viewContext = main queue)
let context = stack.viewContext             // main thread context
let entities = try context.fetch(request)  // SQLite read on main thread
entities.map { $0.toTransaction() }        // fault 19k objects on main thread
// → blocks main thread for hundreds of milliseconds
```

**Files:**
- Modify: `AIFinanceManager/Services/Repository/TransactionRepository.swift:42-77`
- Modify: `AIFinanceManager/ViewModels/TransactionStore.swift:182-210`

**Step 1: Change `loadTransactions` to use background context**

In `TransactionRepository.swift`, replace the entire `loadTransactions(dateRange:)` method:

```swift
func loadTransactions(dateRange: DateInterval? = nil) -> [Transaction] {
    PerformanceProfiler.start("TransactionRepository.loadTransactions")

    // PERFORMANCE: Use background context — never block the main thread for 19k entities.
    // `performAndWait` is synchronous but runs on the context's own serial queue (background thread).
    let bgContext = stack.newBackgroundContext()
    var transactions: [Transaction] = []

    bgContext.performAndWait {
        let request = TransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        // fetchBatchSize is meaningful here: we iterate the full array but CoreData
        // loads entity data in batches of 500 instead of all at once.
        request.fetchBatchSize = 500

        if let dateRange = dateRange {
            request.predicate = NSPredicate(
                format: "date >= %@ AND date <= %@",
                dateRange.start as NSDate,
                dateRange.end as NSDate
            )
        }

        do {
            let entities = try bgContext.fetch(request)
            transactions = entities.map { $0.toTransaction() }
        } catch {
            // fallback handled below
        }
    }

    PerformanceProfiler.end("TransactionRepository.loadTransactions")

    if transactions.isEmpty {
        return userDefaultsRepository.loadTransactions(dateRange: dateRange)
    }
    return transactions
}
```

**Step 2: Make `TransactionStore.loadData()` truly async via background context**

The protocol method `loadTransactions` is synchronous, but we wrap it in a detached task inside `loadData()` so the MainActor is free while waiting.

In `TransactionStore.swift`, replace `loadData()`:

```swift
func loadData() async throws {
    // PERFORMANCE: All CoreData fetches run on a background context via Task.detached.
    // MainActor is NOT blocked — it awaits the background result.
    let (txs, accs, cats, subs, catLinks, txLinks, series, occurrences) = try await Task.detached(priority: .userInitiated) {
        let repo = await self.repository
        let txs   = repo.loadTransactions(dateRange: nil)
        let accs  = repo.loadAccounts()
        let cats  = repo.loadCategories()
        let subs  = repo.loadSubcategories()
        let catLinks = repo.loadCategorySubcategoryLinks()
        let txLinks  = repo.loadTransactionSubcategoryLinks()
        let series   = repo.loadRecurringSeries()
        let occ      = repo.loadRecurringOccurrences()
        return (txs, accs, cats, subs, catLinks, txLinks, series, occ)
    }.value

    // Back on MainActor — single batch assignment triggers one @Observable update cycle
    accounts = AccountOrderManager.shared.applyOrders(to: accs)
    transactions = txs
    categories = CategoryOrderManager.shared.applyOrders(to: cats)
    subcategories = subs
    categorySubcategoryLinks = catLinks
    transactionSubcategoryLinks = txLinks
    recurringSeries = series
    recurringOccurrences = occurrences
}
```

> **Note on `Task.detached` + `await self.repository`**: `repository` is `@ObservationIgnored let` so it's safe to capture across actor boundaries. Since `DataRepositoryProtocol` methods are synchronous and `CoreDataRepository` uses `CoreDataStack.shared` (marked `@unchecked Sendable`), the detached closure is safe.

**Step 3: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED` — no concurrency errors because `repository` is `@ObservationIgnored`.

**Step 4: Run unit tests**

```bash
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:AIFinanceManagerTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

**Step 5: Commit**

```bash
git add AIFinanceManager/Services/Repository/TransactionRepository.swift \
        AIFinanceManager/ViewModels/TransactionStore.swift
git commit -m "perf(startup): move CoreData fetch to background context — unblock MainActor (Phase 28-B)"
```

---

## Task 4: Two-phase balance registration

**Time:** ~25 min
**Risk:** 🟢 Low — additive change, balance values already persisted in CoreData
**Impact:** Removes O(N×M) transaction scan from startup critical path for `shouldCalculateFromTransactions` accounts

**Current bottleneck:**
```swift
// AppCoordinator.initialize():
await balanceCoordinator.registerAccounts(
    transactionStore.accounts,
    transactions: transactionStore.transactions  // ← passes ALL 19k transactions
)
// Inside registerAccounts: for each shouldCalculateFromTransactions account,
// engine.calculateBalance(account:transactions:19k) → O(N) per account
```

**Files:**
- Modify: `AIFinanceManager/Services/Balance/BalanceCoordinator.swift:82-128`
- Modify: `AIFinanceManager/ViewModels/AppCoordinator.swift` (initialize method)

**Step 1: Add fast-path to `registerAccounts`**

In `BalanceCoordinator.swift`, replace `registerAccounts(_:transactions:)` with two-phase approach:

```swift
/// Phase A (instant): Use persisted `account.balance` for all accounts.
/// Phase B (background): Recalculate `shouldCalculateFromTransactions` accounts from transaction history.
func registerAccounts(_ accounts: [Account], transactions: [Transaction] = []) async {
    // ── Phase A: instant balance display ────────────────────────────────────
    var accountBalances: [AccountBalance] = []
    var phase1Balances: [String: Double] = [:]

    for account in accounts {
        let ab = AccountBalance(
            accountId: account.id,
            currentBalance: account.initialBalance ?? 0,
            initialBalance: account.initialBalance,
            depositInfo: account.depositInfo,
            currency: account.currency,
            isDeposit: account.isDeposit
        )
        accountBalances.append(ab)
        // Use persisted balance for ALL accounts immediately.
        // `account.balance` is updated synchronously by persistBalance() on every mutation,
        // so it is always accurate as long as the app didn't crash mid-write.
        phase1Balances[account.id] = account.balance
    }

    store.registerAccounts(accountBalances)
    store.updateBalances(phase1Balances, source: .manual)
    cache.setBalances(phase1Balances)

    // Publish immediately — UI shows balances with zero delay
    var merged = self.balances
    for (id, bal) in phase1Balances { merged[id] = bal }
    self.balances = merged

    // ── Phase B: accurate recalculation for dynamic accounts (background) ──
    // Only needed if any accounts use shouldCalculateFromTransactions.
    let dynamicAccounts = accounts.filter { $0.shouldCalculateFromTransactions }
    guard !dynamicAccounts.isEmpty, !transactions.isEmpty else { return }

    Task.detached(priority: .utility) { [weak self, dynamicAccounts, transactions] in
        guard let self else { return }
        var phase2Balances: [String: Double] = [:]

        for account in dynamicAccounts {
            guard let ab = await self.store.getAccount(account.id) else { continue }
            let calculated = await self.engine.calculateBalance(
                account: ab,
                transactions: transactions,
                mode: .fromInitialBalance
            )
            phase2Balances[account.id] = calculated
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.store.updateBalances(phase2Balances, source: .recalculation)
            self.cache.setBalances(phase2Balances)
            var merged = self.balances
            for (id, bal) in phase2Balances { merged[id] = bal }
            self.balances = merged
        }
    }
}
```

> **Note on `store` and `engine` access from Task.detached**: Both `store: BalanceStore` and `engine: BalanceCalculationEngine` are `private let` on `BalanceCoordinator`. Since `BalanceCoordinator` is `@MainActor`, we need to pass them explicitly or mark them `nonisolated`. The simplest fix: capture `dynamicAccounts` and `transactions` as value types, and call a `@MainActor` helper after the background calculation:
>
> Alternatively, perform the actual calculation in background by making `BalanceCalculationEngine.calculateBalance` a static function or by passing the relevant data in:

Simpler version that avoids actor isolation complexity:

```swift
// Phase B: detach only the CPU work, engine called via @MainActor helper
Task(priority: .utility) { [weak self] in
    guard let self else { return }
    // Task(priority:) inherits @MainActor from BalanceCoordinator
    // Use Task.detached only for pure CPU work with captured value types
    let results = await Task.detached(priority: .utility) { [dynamicAccounts, transactions, engine = self.engine, store = self.store] in
        var phase2: [String: Double] = [:]
        for account in dynamicAccounts {
            guard let ab = store.getAccount(account.id) else { continue }
            let calc = engine.calculateBalance(account: ab, transactions: transactions, mode: .fromInitialBalance)
            phase2[account.id] = calc
        }
        return phase2
    }.value
    // Back on MainActor
    store.updateBalances(results, source: .recalculation)
    var merged = self.balances
    for (id, bal) in results { merged[id] = bal }
    self.balances = merged
}
```

> `BalanceStore` and `BalanceCalculationEngine` are not actor-isolated (they're plain classes). Mark them `@unchecked Sendable` if Swift 6 raises warnings.

**Step 2: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

**Step 3: Commit**

```bash
git add AIFinanceManager/Services/Balance/BalanceCoordinator.swift
git commit -m "perf(startup): two-phase balance registration — instant display then background recalc (Phase 28-D)"
```

---

## Task 5: Add targeted persist methods to protocol and repository

**Time:** ~30 min
**Risk:** 🟢 Low — purely additive, existing methods untouched
**Impact:** Foundation for Task 6. Provides O(1) insert/update instead of O(3N) full-table-scan

**Files:**
- Modify: `AIFinanceManager/Services/Core/DataRepositoryProtocol.swift`
- Modify: `AIFinanceManager/Services/Repository/TransactionRepository.swift`
- Modify: `AIFinanceManager/Services/Repository/CoreDataRepository.swift`

**Step 1: Add methods to `DataRepositoryProtocol`**

```swift
// Add to MARK: - Transactions section in DataRepositoryProtocol.swift:

/// Insert a single new transaction. O(1) — does NOT fetch existing records.
/// Use for add operations. Prerequisite: transaction.id must be non-empty.
func insertTransaction(_ transaction: Transaction)

/// Update fields of a single existing transaction by ID. O(1) — fetches by PK only.
/// Use for update operations.
func updateTransactionFields(_ transaction: Transaction)

/// Batch-insert multiple new transactions using NSBatchInsertRequest.
/// O(N) but bypasses NSManagedObject overhead — ideal for CSV import.
/// Note: does NOT set CoreData relationships (account/recurringSeries).
/// accountId/targetAccountId stored as String columns are used as fallback.
func batchInsertTransactions(_ transactions: [Transaction])
```

**Step 2: Implement in `TransactionRepository.swift`**

Add after `deleteTransactionImmediately`:

```swift
// MARK: - Targeted Persist Methods (Phase 28-C)

func insertTransaction(_ transaction: Transaction) {
    let bgContext = stack.newBackgroundContext()
    bgContext.perform {
        // Create entity
        let entity = TransactionEntity.from(transaction, context: bgContext)

        // Resolve account relationship (best-effort; accountId String is the fallback)
        if let accountId = transaction.accountId, !accountId.isEmpty {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", accountId)
            req.fetchLimit = 1
            entity.account = try? bgContext.fetch(req).first
        }

        if let targetId = transaction.targetAccountId, !targetId.isEmpty {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", targetId)
            req.fetchLimit = 1
            entity.targetAccount = try? bgContext.fetch(req).first
        }

        if let seriesId = transaction.recurringSeriesId, !seriesId.isEmpty {
            let req = RecurringSeriesEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", seriesId)
            req.fetchLimit = 1
            entity.recurringSeries = try? bgContext.fetch(req).first
        }

        try? bgContext.save()
    }
}

func updateTransactionFields(_ transaction: Transaction) {
    let bgContext = stack.newBackgroundContext()
    bgContext.perform {
        let req = TransactionEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", transaction.id)
        req.fetchLimit = 1
        guard let entity = try? bgContext.fetch(req).first else { return }

        entity.date            = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
        entity.descriptionText = transaction.description
        entity.amount          = transaction.amount
        entity.currency        = transaction.currency
        entity.convertedAmount = transaction.convertedAmount ?? 0
        entity.type            = transaction.type.rawValue
        entity.category        = transaction.category
        entity.subcategory     = transaction.subcategory
        entity.targetAmount    = transaction.targetAmount ?? 0
        entity.targetCurrency  = transaction.targetCurrency
        entity.accountId       = transaction.accountId
        entity.targetAccountId = transaction.targetAccountId
        entity.accountName     = transaction.accountName
        entity.targetAccountName = transaction.targetAccountName

        try? bgContext.save()
    }
}

func batchInsertTransactions(_ transactions: [Transaction]) {
    guard !transactions.isEmpty else { return }
    let bgContext = stack.newBackgroundContext()
    bgContext.perform {
        // NSBatchInsertRequest (iOS 14+): inserts directly into SQLite,
        // bypassing NSManagedObject lifecycle — ideal for CSV import of 1k+ records.
        // Relationships are NOT set (no account/recurringSeries references).
        // toTransaction() uses accountId/targetAccountId String columns as fallbacks — safe.
        let dicts: [[String: Any]] = transactions.map { tx in
            var dict: [String: Any] = [:]
            dict["id"]             = tx.id
            dict["date"]           = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
            dict["descriptionText"] = tx.description
            dict["amount"]         = tx.amount
            dict["currency"]       = tx.currency
            dict["convertedAmount"] = tx.convertedAmount ?? 0.0
            dict["type"]           = tx.type.rawValue
            dict["category"]       = tx.category
            dict["subcategory"]    = tx.subcategory ?? ""
            dict["targetAmount"]   = tx.targetAmount ?? 0.0
            dict["targetCurrency"] = tx.targetCurrency ?? ""
            dict["accountId"]      = tx.accountId ?? ""
            dict["targetAccountId"] = tx.targetAccountId ?? ""
            dict["accountName"]    = tx.accountName ?? ""
            dict["targetAccountName"] = tx.targetAccountName ?? ""
            dict["createdAt"]      = Date(timeIntervalSince1970: tx.createdAt)
            return dict
        }

        let insertRequest = NSBatchInsertRequest(entityName: "TransactionEntity", objects: dicts)
        insertRequest.resultType = .statusOnly
        _ = try? bgContext.execute(insertRequest)

        // Merge batch changes into viewContext so @Observable picks them up
        bgContext.refreshAllObjects()
    }
}
```

**Step 3: Add to `CoreDataRepository.swift` facade**

```swift
// Add in MARK: - Transactions section:

func insertTransaction(_ transaction: Transaction) {
    transactionRepository.insertTransaction(transaction)
}

func updateTransactionFields(_ transaction: Transaction) {
    transactionRepository.updateTransactionFields(transaction)
}

func batchInsertTransactions(_ transactions: [Transaction]) {
    transactionRepository.batchInsertTransactions(transactions)
}
```

**Step 4: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

**Step 5: Commit**

```bash
git add AIFinanceManager/Services/Core/DataRepositoryProtocol.swift \
        AIFinanceManager/Services/Repository/TransactionRepository.swift \
        AIFinanceManager/Services/Repository/CoreDataRepository.swift
git commit -m "feat(repository): add insertTransaction, updateTransactionFields, batchInsertTransactions — O(1)/O(N) targeted persist (Phase 28-C prep)"
```

---

## Task 6: Replace `saveTransactions` with `persistIncremental` in TransactionStore

**Time:** ~20 min
**Risk:** 🟡 Medium — changes how mutations are persisted; deletion already handled
**Impact:** O(3N)=57k ops per mutation → O(1). Eliminates the biggest post-startup performance bottleneck.

**Important invariant:**
- `.deleted` events: `deleteTransactionImmediately(id:)` is already called in `invalidateCache(for:)` — no change needed
- `.added` events: use new `insertTransaction`
- `.updated` events: use new `updateTransactionFields`
- `.bulkAdded` events: use new `batchInsertTransactions` (Task 7 wires this up properly)
- Series events: keep `saveRecurringSeries` / `saveRecurringOccurrences` (small datasets)

**Files:**
- Modify: `AIFinanceManager/ViewModels/TransactionStore.swift:1056-1070`

**Step 1: Replace `persist()` with `persistIncremental(_ event:)`**

In `TransactionStore.swift`, replace:

```swift
/// Persist current state to repository
private func persist() async {
    repository.saveTransactions(transactions)
    repository.saveRecurringSeries(recurringSeries)
    repository.saveRecurringOccurrences(recurringOccurrences)
}
```

With:

```swift
/// Phase 28-C: Incremental persist — O(1) per transaction event.
/// OLD: saveTransactions([all 19k]) = O(3N) = 57k ops per mutation.
/// NEW: targeted insert/update/delete = O(1) per mutation.
private func persistIncremental(_ event: TransactionEvent) {
    switch event {
    case .added(let tx):
        // insertTransaction creates one CoreData entity — O(1)
        repository.insertTransaction(tx)

    case .deleted:
        // deleteTransactionImmediately already called in invalidateCache(for:) — no-op here
        break

    case .updated(_, let new):
        // updateTransactionFields fetches by PK and updates fields — O(1)
        repository.updateTransactionFields(new)

    case .bulkAdded(let txs):
        // NSBatchInsertRequest — O(N) but fast (bypasses managed object overhead)
        repository.batchInsertTransactions(txs)

    case .seriesCreated, .seriesUpdated, .seriesStopped, .seriesDeleted:
        // Recurring series are small datasets — keep existing full-save approach
        repository.saveRecurringSeries(recurringSeries)
        repository.saveRecurringOccurrences(recurringOccurrences)
    }
}
```

**Step 2: Wire `persistIncremental` into `apply()`**

In `apply(_ event:)`, replace `await persist()` with `persistIncremental(event)`:

```swift
// BEFORE:
if !isImporting {
    await persist()
}

// AFTER:
if !isImporting {
    persistIncremental(event)  // no longer async — all saves are fire-and-forget on background context
}
```

Note: `apply()` signature stays `async throws` since `updateBalances` still uses async. Just remove `await` from the persist call.

**Step 3: Keep `persist()` for `finishImport()` cleanup path**

`finishImport()` already uses the Sync versions (`saveTransactionsSync`) — leave that unchanged. Only the hot-path `apply()` is changed.

**Step 4: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

**Step 5: Run unit tests**

```bash
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:AIFinanceManagerTests \
  2>&1 | grep -E "passed|failed|BUILD"
```

**Step 6: Commit**

```bash
git add AIFinanceManager/ViewModels/TransactionStore.swift
git commit -m "perf(store): replace saveTransactions O(3N) with persistIncremental O(1) per mutation (Phase 28-C)"
```

---

## Task 7: NSBatchInsertRequest for CSV bulk import + merge to viewContext

**Time:** ~25 min
**Risk:** 🟡 Medium — changes CSV import persist path
**Impact:** CSV import of 1000 tx: ~10s → <1s. `NSBatchInsertRequest` bypasses managed object lifecycle.

**Problem:** After `batchInsertTransactions` writes directly to SQLite via `NSBatchInsertRequest`, the `viewContext` doesn't automatically see the new entities. We need to merge them.

**Files:**
- Modify: `AIFinanceManager/Services/Repository/TransactionRepository.swift` (batchInsertTransactions)
- Modify: `AIFinanceManager/CoreData/CoreDataStack.swift` (add merge helper)

**Step 1: Add `mergeChangesFromBatchOperation` helper to `CoreDataStack`**

In `CoreDataStack.swift`, add after `batchUpdate(_ :)`:

```swift
/// Merge NSBatchInsertRequest / NSBatchDeleteRequest result IDs into viewContext.
/// Must be called after executing any batch operation to keep viewContext in sync.
func mergeBatchResult(_ result: NSPersistentStoreResult?, for key: String = NSInsertedObjectIDsKey) {
    guard let batchResult = result as? NSBatchInsertResult,
          let objectIDs = batchResult.result as? [NSManagedObjectID],
          !objectIDs.isEmpty else { return }
    let changes = [key: objectIDs]
    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
}
```

**Step 2: Update `batchInsertTransactions` to merge into viewContext**

In `TransactionRepository.swift`, update `batchInsertTransactions`:

```swift
func batchInsertTransactions(_ transactions: [Transaction]) {
    guard !transactions.isEmpty else { return }
    let bgContext = stack.newBackgroundContext()
    bgContext.perform { [weak self] in
        guard let self else { return }
        let dicts: [[String: Any]] = transactions.map { tx in
            var dict: [String: Any] = [:]
            dict["id"]              = tx.id
            dict["date"]            = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
            dict["descriptionText"] = tx.description
            dict["amount"]          = tx.amount
            dict["currency"]        = tx.currency
            dict["convertedAmount"] = tx.convertedAmount ?? 0.0
            dict["type"]            = tx.type.rawValue
            dict["category"]        = tx.category
            dict["subcategory"]     = tx.subcategory ?? ""
            dict["targetAmount"]    = tx.targetAmount ?? 0.0
            dict["targetCurrency"]  = tx.targetCurrency ?? ""
            dict["accountId"]       = tx.accountId ?? ""
            dict["targetAccountId"] = tx.targetAccountId ?? ""
            dict["accountName"]     = tx.accountName ?? ""
            dict["targetAccountName"] = tx.targetAccountName ?? ""
            dict["createdAt"]       = Date(timeIntervalSince1970: tx.createdAt)
            return dict
        }

        let insertRequest = NSBatchInsertRequest(entityName: "TransactionEntity", objects: dicts)
        insertRequest.resultType = .objectIDs  // needed for mergeChanges
        let result = try? bgContext.execute(insertRequest) as? NSBatchInsertResult

        // Merge inserted object IDs into viewContext so @Observable picks them up
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stack.mergeBatchResult(result, for: NSInsertedObjectIDsKey)
        }
    }
}
```

**Step 3: Build and verify**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

**Step 4: Test CSV import manually**

Run on simulator, import a CSV file with 500+ transactions. Verify:
- Import completes in <2 seconds
- All transactions appear in History view
- Account balances are correct after import

**Step 5: Run unit tests**

```bash
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:AIFinanceManagerTests \
  2>&1 | grep -E "passed|failed|BUILD"
```

**Step 6: Commit**

```bash
git add AIFinanceManager/Services/Repository/TransactionRepository.swift \
        AIFinanceManager/CoreData/CoreDataStack.swift
git commit -m "perf(import): NSBatchInsertRequest + viewContext merge for CSV bulk import (Phase 28-G)"
```

---

## CLAUDE.md Update

After all tasks are complete, update `CLAUDE.md` to document Phase 28:

```markdown
**Phase 28** (2026-02-23): Instant Launch — Startup Performance
- **Progressive UI**: `initializeFastPath()` loads accounts only (<50ms); full data loads in background
- **Background CoreData fetch**: `loadTransactions` moved from `viewContext` to `newBackgroundContext()` + `performAndWait` — unblocks MainActor during 19k entity materialization
- **Two-phase balance registration**: Phase A uses persisted `account.balance` (instant); Phase B recalculates `shouldCalculateFromTransactions` accounts in background
- **Deferred recurring generation**: `generateRecurringTransactions()` moved to background Task post-load
- **Incremental persist O(1)**: `persistIncremental(_:)` replaces `saveTransactions([19k])` — `insertTransaction`/`updateTransactionFields`/`batchInsertTransactions` per event
- **NSBatchInsertRequest**: CSV bulk import bypasses NSManagedObject overhead — 10x faster for 1k+ records
- Design doc: `docs/plans/2026-02-23-startup-performance-instant-launch.md`
```

---

## Summary: Expected Improvements

| Metric | Before | After |
|--------|--------|-------|
| Time to first pixel (home screen) | ~2-4s (full spinner) | <100ms (fast-path) |
| CoreData fetch thread | Main thread (blocks UI) | Background context |
| Ops per single transaction add | ~57,000 (O(3N)) | ~3 (O(1)) |
| Balance display at startup | After O(N×M) recalc | Instant (persisted value) |
| CSV import 1000 rows | ~10s | <1s (NSBatchInsertRequest) |
| Recurring generation | Blocks startup | Background post-load |

---

## Future Phase 29: Sliding Window (optional, high complexity)

If 19k transaction count continues growing, consider keeping only the last N months in `TransactionStore.transactions` (hot window), loading older data on demand in History view via pagination. All aggregates/insights already use CoreData aggregate entities (Phase 22), so this would primarily benefit the in-memory footprint and initial load time further.

**Pre-requisites:** All Phase 28 tasks complete. Add `loadTransactions(since:limit:)` and `countTransactions()` to `DataRepositoryProtocol`.
