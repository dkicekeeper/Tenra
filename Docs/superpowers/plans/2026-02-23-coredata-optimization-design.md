# CoreData Optimization Design — Phase 31

**Date:** 2026-02-23
**Author:** SwiftUI Expert Skill
**Scope:** Performance audit + phased optimization plan
**Scale:** 19k → 50–100k transactions

---

## Background

Comprehensive audit of the CoreData layer revealed 12 issues across three severity levels. The app currently holds all 19k+ transactions in memory (TransactionStore), has N+1 query patterns in save operations, nested `context.perform` anti-patterns (deadlock risk), and no pagination for the transaction list.

User reports: slow launch, UI freezes on scroll/animations, slow save/delete operations.

---

## Phase A — Critical Fixes (0 regressions, immediately noticeable)

### A1. Remove Nested `context.perform` in BudgetSpendingCacheService

**Problem:** `incrementSpent()` and `performRebuild()` call `context.perform { }` inside an already-active `await context.perform { }` block. The inner `perform` is queued on the same serial queue — causing a race or potential deadlock in Swift Concurrency.

**File:** `Services/Categories/BudgetSpendingCacheService.swift`

**Fix:** Remove all inner `context.perform` calls. CoreData entity mutations are safe to call directly when already executing inside `await context.perform { }`:

```swift
// ❌ Before:
await context.perform {
    guard let entity = try? context.fetch(request).first else { return }
    context.perform {           // ← nested perform, dangerous
        entity.cachedSpentAmount += delta
        entity.cachedSpentCurrency = currency
        entity.cachedSpentUpdatedAt = Date()
    }
    try? context.save()
}

// ✅ After:
await context.perform {
    guard let entity = try? context.fetch(request).first else { return }
    entity.cachedSpentAmount += delta              // ← direct mutation, safe
    entity.cachedSpentCurrency = currency
    entity.cachedSpentUpdatedAt = Date()
    try? context.save()
}
```

**Also fix:** `RecurringRepository.updateRecurringSeriesEntity()` wraps mutations in `context.perform { }` inside a `nonisolated` function that is called from within `context.perform` in `saveRecurringSeries()`.

### A2. Move main-thread CoreData reads to background contexts

**Problem:** Two methods use `stack.viewContext` (main thread) for non-trivial reads, risking MainActor stalls.

**Files:**
- `AccountRepository.loadAllAccountBalances()` — fetches full AccountEntity objects just for `id` and `balance`
- `CategoryRepository.loadCategoryRules()` — fetches full CategoryRuleEntity on main thread

**Fix A2a — Partial fetch (dictionaryResultType) for `loadAllAccountBalances()`:**

```swift
// ❌ Before: full objects on main thread
let context = stack.viewContext
let entities = try context.fetch(AccountEntity.fetchRequest())
return Dictionary(uniqueKeysWithValues: entities.compactMap { ($0.id!, $0.balance) })

// ✅ After: partial fetch on background thread — no NSManagedObject created
let bgContext = stack.newBackgroundContext()
var balances: [String: Double] = [:]
bgContext.performAndWait {
    let request = NSFetchRequest<NSDictionary>(entityName: "AccountEntity")
    request.resultType = .dictionaryResultType
    request.propertiesToFetch = ["id", "balance"]    // scalar read only
    if let dicts = try? bgContext.fetch(request) as? [[String: Any]] {
        for dict in dicts {
            if let id = dict["id"] as? String, let bal = dict["balance"] as? Double {
                balances[id] = bal
            }
        }
    }
}
return balances
```

**Fix A2b — Move `loadCategoryRules()` to background context:**

```swift
// Same pattern: background context + performAndWait
```

### A3. Replace `saveCategoryRules()` delete-all + recreate with NSBatchDeleteRequest

**Problem:** On every save, ALL rules are fetched, ALL are deleted, ALL are recreated. O(3N) even for a single change.

**File:** `CategoryRepository.swift`

**Fix:** Use `NSBatchDeleteRequest` to clear, then batch insert new rules:

```swift
// ❌ Before: O(3N) — fetch all, delete all, create all
for entity in existingEntities { context.delete(entity) }
for rule in rules { _ = CategoryRuleEntity.from(rule, context: context) }

// ✅ After: NSBatchDeleteRequest + batch create
let deleteRequest = NSBatchDeleteRequest(
    fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "CategoryRuleEntity")
)
deleteRequest.resultType = .resultTypeObjectIDs
let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
let ids = result?.result as? [NSManagedObjectID] ?? []
NSManagedObjectContext.mergeChanges(
    fromRemoteContextSave: [NSDeletedObjectsKey: ids],
    into: [stack.viewContext]
)
// Then create new rules
for rule in rules { _ = CategoryRuleEntity.from(rule, context: context) }
try context.save()
```

### A4. Fix N+1 in `RecurringRepository.saveRecurringSeries()`

**Problem:** For each series item, a separate `fetchAccountSync(id:)` is called — one `SELECT * WHERE id = ?` per item. Pattern already fixed in `TransactionRepository.saveTransactionsSync()` (uses `accountDict`).

**File:** `RecurringRepository.swift`

**Fix:** Pre-fetch all relevant accounts into a dictionary, then O(1) lookup:

```swift
// ❌ Before: N separate SELECT calls
for item in series {
    if let accountId = item.accountId {
        entity.account = fetchAccountSync(id: accountId, context: context)  // ← N times
    }
}

// ✅ After: 1 SELECT + dictionary lookup
let accountIds = Set(series.compactMap { $0.accountId })
let accountRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
accountRequest.predicate = NSPredicate(format: "id IN %@", accountIds)
accountRequest.fetchBatchSize = 50
let accountDict = Dictionary(
    uniqueKeysWithValues: (try? context.fetch(accountRequest) ?? []).compactMap {
        $0.id.map { ($0, $0) }
    }
)
for item in series {
    if let accountId = item.accountId {
        entity.account = accountDict[accountId]    // ← O(1)
    }
}
```

---

## Phase B — Performance and Memory

### B1. Add `fetchBatchSize` to all repositories

CoreData batch faulting: entity data is loaded in batches, not all at once. Without `fetchBatchSize`, all attributes are loaded into memory immediately.

| Repository | Method | Add |
|---|---|---|
| `AccountRepository` | `loadAccounts()` | `fetchBatchSize = 50` |
| `CategoryRepository` | `loadCategories()`, `loadSubcategories()`, `loadCategorySubcategoryLinks()`, `loadTransactionSubcategoryLinks()` | `fetchBatchSize = 100` |
| `RecurringRepository` | `loadRecurringSeries()`, `loadRecurringOccurrences()` | `fetchBatchSize = 100` |
| `CategoryAggregateService` | all fetch methods | `fetchBatchSize = 200` |
| `MonthlyAggregateService` | all fetch methods | `fetchBatchSize = 200` |
| `BudgetSpendingCacheService` | `cachedSpent()` | `fetchBatchSize = 50` |

### B2. NSFetchedResultsController for transaction list (TransactionPaginationController)

**Problem:** TransactionStore holds all 19k+ transactions in memory as `[Transaction]`. At 100k, this is 40–80 MB + render cost for 19k cells.

**New component:** `TransactionPaginationController` — standalone `@Observable @MainActor` object, owns the FRC, exposes paginated sections to the UI.

```swift
@Observable @MainActor
final class TransactionPaginationController: NSObject, NSFetchedResultsControllerDelegate {
    @ObservationIgnored private var frc: NSFetchedResultsController<TransactionEntity>?

    // Exposed to UI
    private(set) var sections: [TransactionSection] = []
    private(set) var totalCount: Int = 0

    // Filters
    var searchQuery: String = "" { didSet { applyFilters() } }
    var selectedAccountId: String? { didSet { applyFilters() } }
    var dateRange: ClosedRange<Date>? { didSet { applyFilters() } }

    func setup(stack: CoreDataStack) {
        let request = TransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize = 50     // Only visible rows in memory

        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: stack.viewContext,
            sectionNameKeyPath: "dateSectionKey",   // grouped by day
            cacheName: "transactions-main"           // disk-cached sections
        )
        frc?.delegate = self
        performFetch()
    }

    private func applyFilters() {
        var predicates: [NSPredicate] = []
        if !searchQuery.isEmpty {
            predicates.append(NSPredicate(format: "descriptionText CONTAINS[cd] %@ OR category CONTAINS[cd] %@", searchQuery, searchQuery))
        }
        if let accountId = selectedAccountId {
            predicates.append(NSPredicate(format: "accountId == %@", accountId))
        }
        if let range = dateRange {
            predicates.append(NSPredicate(format: "date >= %@ AND date <= %@", range.lowerBound as NSDate, range.upperBound as NSDate))
        }
        frc?.fetchRequest.predicate = predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        NSFetchedResultsController<TransactionEntity>.deleteCache(withName: "transactions-main")
        performFetch()
    }

    // MARK: - NSFetchedResultsControllerDelegate
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateSections()
    }
}
```

**Architecture impact:**
- `TransactionStore.transactions: [Transaction]` → kept only for business logic (balance, insights, recurring)
- History view / main list → uses `TransactionPaginationController`
- AppCoordinator creates and owns `TransactionPaginationController`
- Existing ViewModels that need full transaction list for computation (InsightsViewModel, BalanceCoordinator) continue reading from TransactionStore

**`dateSectionKey`:** Computed transient string property on TransactionEntity:
```swift
// TransactionEntity extension
@objc var dateSectionKey: String {
    guard let date = self.date else { return "Unknown" }
    return DateFormatters.sectionFormatter.string(from: date)  // "2026-02-23"
}
```

### B3. Persistent History Tracking cleanup

`NSPersistentHistoryTrackingKey = true` is enabled but no cleanup is scheduled. The history table (`ZTRANSACTION`, `ZHISTORY`) grows unboundedly.

**Fix:** Add to `CoreDataStack`:

```swift
func purgeHistory(olderThan days: Int = 7) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
    do {
        try viewContext.execute(purgeRequest)
    } catch {
        logger.error("Failed to purge persistent history: \(error)")
    }
}
```

**Schedule:** Call from `AppCoordinator.initialize()` after full load, once per app launch:

```swift
Task(priority: .background) {
    stack.purgeHistory(olderThan: 7)
}
```

### B4. Remove `spotlightIndexingEnabled` from `CategoryAggregateEntity.day`

**Problem:** In the xcdatamodel, `CategoryAggregateEntity.day` has `spotlightIndexingEnabled="YES"`. This triggers CoreData to build a Spotlight index for aggregate data — completely useless for financial aggregates and wastes system resources.

**Fix:** Open `AIFinanceManager.xcdatamodeld`, select `CategoryAggregateEntity` → `day` attribute → uncheck "Index in Spotlight". Lightweight migration, no new model version needed.

---

## Phase C — Scale to 100k

### C1. TransactionStore Windowing Strategy

**Problem:** At 100k transactions, keeping all in `TransactionStore.transactions` is unsustainable (~40–80 MB array, O(N) computations).

**Strategy:** TransactionStore loads a rolling window of the last N months for business logic. FRC handles the full list in UI.

```swift
// TransactionStore
private let windowMonths: Int = 3  // configurable via Settings

func loadData() async throws {
    let windowStart = Calendar.current.date(
        byAdding: .month, value: -windowMonths, to: Date()
    )
    let transactions = repo.loadTransactions(dateRange: windowStart.map { DateRange($0, Date()) })
    // Aggregates (Phase 22) cover full history for insights
}
```

**InsightsService** reads from `CategoryAggregateService` and `MonthlyAggregateService` (Phase 22) — no longer needs full transaction array. Already O(M) where M = months.

### C2. NSBatchUpdateRequest for bulk balance updates

For `AccountRepository.updateAccountBalancesSync()` when updating more than ~20 accounts:

```swift
// Per-account NSBatchUpdateRequest
func updateAccountBalancesBatch(_ balances: [String: Double]) async throws {
    for (accountId, newBalance) in balances {
        let batchUpdate = NSBatchUpdateRequest(entityName: "AccountEntity")
        batchUpdate.predicate = NSPredicate(format: "id == %@", accountId)
        batchUpdate.propertiesToUpdate = ["balance": newBalance]
        batchUpdate.resultType = .updatedObjectIDsResultType

        let bgContext = stack.newBackgroundContext()
        await bgContext.perform {
            let result = try bgContext.execute(batchUpdate) as! NSBatchUpdateResult
            DispatchQueue.main.async {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSUpdatedObjectsKey: result.result as! [NSManagedObjectID]],
                    into: [self.stack.viewContext]
                )
            }
        }
    }
}
```

### C3. Additional indexes for Insights queries

Add to `TransactionEntity` in CoreData model (new model version required):

| Index name | Properties | Purpose |
|---|---|---|
| `byCurrencyDateIndex` | `currency ASC`, `date DESC` | Multi-currency insights filter |
| `byTypeCurrencyDateIndex` | `type ASC`, `currency ASC`, `date DESC` | Income/expense by currency + period |

**Note:** These indexes add write overhead. Only add when profiling shows they help. Use Instruments → Core Data template to verify query plans first.

### C4. CoreData Model Version 2

Create `AIFinanceManager v2.xcdatamodeld` for:
1. Remove `spotlightIndexingEnabled` from `CategoryAggregateEntity.day`
2. Add `byCurrencyDateIndex` and `byTypeCurrencyDateIndex` on `TransactionEntity`
3. Lightweight migration (no NSMappingModel needed — only index changes)

Model versions enable controlled migrations without data loss. Always increment for schema changes.

---

## Implementation Order

| Step | Task | Phase | Risk |
|---|---|---|---|
| 1 | Fix nested `context.perform` in BudgetSpendingCacheService | A1 | 🟢 Low |
| 2 | Fix `updateRecurringSeriesEntity` nested perform | A1 | 🟢 Low |
| 3 | Move `loadAllAccountBalances` to background + dictionaryResultType | A2 | 🟡 Medium |
| 4 | Move `loadCategoryRules` to background context | A2 | 🟢 Low |
| 5 | Replace `saveCategoryRules` with NSBatchDeleteRequest | A3 | 🟡 Medium |
| 6 | Fix N+1 in `saveRecurringSeries` with pre-fetched accountDict | A4 | 🟢 Low |
| 7 | Add `fetchBatchSize` across all repositories | B1 | 🟢 Low |
| 8 | Create `TransactionPaginationController` with NSFetchedResultsController | B2 | 🔴 High |
| 9 | Wire FRC into History/transaction list views | B2 | 🔴 High |
| 10 | Add `purgeHistory` to CoreDataStack + schedule in AppCoordinator | B3 | 🟢 Low |
| 11 | Remove `spotlightIndexingEnabled` from `CategoryAggregateEntity.day` | B4 | 🟢 Low |
| 12 | TransactionStore windowing strategy | C1 | 🔴 High |
| 13 | NSBatchUpdateRequest for bulk balance updates | C2 | 🟡 Medium |
| 14 | Create CoreData Model v2 with new indexes | C3/C4 | 🟡 Medium |

---

## Expected Performance Improvements

| Metric | Before | After Phase A | After Phase B | After Phase C |
|---|---|---|---|---|
| `saveCategoryRules()` | O(3N) full replace | O(N) batch delete + insert | — | — |
| `saveRecurringSeries()` | N SELECT + N saves | 1 SELECT + N saves | — | — |
| `loadAllAccountBalances()` | Full objects, main thread | 2-field dict, bg thread | — | — |
| BudgetSpendingCache deadlock risk | Present | Eliminated | — | — |
| Transaction list memory (19k rows) | ~8 MB array | — | ~50 visible rows | — |
| Transaction list memory (100k rows) | ~40 MB array | — | ~50 visible rows | Window only |
| Persistent history growth | Unbounded | — | Bounded (7 days) | — |
| Insights query time | O(N×M) → O(M) (Phase 22) | — | — | O(M) maintained |

---

## Files Affected

**Phase A:**
- `Services/Categories/BudgetSpendingCacheService.swift` (A1)
- `Services/Repository/RecurringRepository.swift` (A1, A4)
- `Services/Repository/AccountRepository.swift` (A2)
- `Services/Repository/CategoryRepository.swift` (A2, A3)

**Phase B:**
- `Services/Repository/TransactionRepository.swift` (B1)
- `Services/Repository/AccountRepository.swift` (B1)
- `Services/Repository/CategoryRepository.swift` (B1)
- `Services/Repository/RecurringRepository.swift` (B1)
- `Services/Categories/CategoryAggregateService.swift` (B1)
- `Services/Balance/MonthlyAggregateService.swift` (B1)
- `Services/Categories/BudgetSpendingCacheService.swift` (B1)
- `CoreData/CoreDataStack.swift` (B3)
- `ViewModels/AppCoordinator.swift` (B2, B3)
- `ViewModels/TransactionPaginationController.swift` (B2, NEW)
- `AIFinanceManager.xcdatamodeld` (B4)
- Transaction list views in `Views/History/` (B2)

**Phase C:**
- `ViewModels/TransactionStore.swift` (C1)
- `Services/Repository/AccountRepository.swift` (C2)
- `AIFinanceManager v2.xcdatamodeld` (C3, C4, NEW)

---

## Architectural Invariants (Do Not Change)

- TransactionStore remains the SSOT for transaction mutations (add/update/delete)
- All writes go through background contexts, never viewContext
- Merge policy: `NSMergeByPropertyObjectTrumpMergePolicy` on all contexts
- `automaticallyMergesChangesFromParent = true` on viewContext (already set)
- Phase 22 aggregate services continue to handle incremental O(1) updates
- Phase 28 incremental persist (O(1) per mutation) remains in place
- Phase 27 constant-size range predicates (7 conditions) must not be reverted
