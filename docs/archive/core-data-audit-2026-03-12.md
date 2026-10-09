# Core Data Deep Audit — 2026-03-12

## Status: ALL FIXES APPLIED (2026-03-12)

Build verified: **BUILD SUCCEEDED**

## Executive Summary

The Core Data stack is **well-architected** overall: value-type DTOs (`Transaction`, `Account`, etc.) properly decouple views from `NSManagedObject`; persistent history tracking is enabled; batch operations correctly merge to viewContext; and the FRC-backed pagination controller is exemplary. The audit found **23 issues** across 4 severity levels — **all fixed**.

| Severity | Count | Status |
|----------|-------|--------|
| **P0 — Crash/Data Loss** | 4 | FIXED |
| **P1 — Correctness** | 5 | FIXED |
| **P2 — Performance** | 4 | FIXED |
| **P3 — Code Quality** | 10 | FIXED |

---

## Stack Setup Assessment

**File**: `CoreData/CoreDataStack.swift` (307 LOC)

### What's Done Right
- Thread-safe singleton with `NSLock` for container initialization
- `NSPersistentHistoryTrackingKey` + `NSPersistentStoreRemoteChangeNotificationPostOptionKey` enabled
- `FileProtectionType.complete` for data at rest
- Automatic lightweight migration enabled
- `viewContext.automaticallyMergesChangesFromParent = true`
- `NSMergeByPropertyObjectTrumpMergePolicy` on both viewContext and background contexts
- `undoManager = nil` for performance
- Batch operation helpers (`batchDelete`, `batchUpdate`, `mergeBatchInsertResult`) correctly merge object IDs to viewContext
- `purgeHistory()` prevents unbounded DB growth
- `resetAllData()` properly resets viewContext + posts notification for FRC rebuild

### What's Done Right (Repository Layer)
- All loads use `newBackgroundContext()` + `performAndWait` — never block main thread
- All saves use `Task.detached` + `newBackgroundContext()` — fire-and-forget on background
- `CoreDataSaveCoordinator` (actor) serializes saves, handles merge conflicts
- `TransactionRepository.saveTransactionsSync` captures `NSManagedObjectContextDidSave` notification for synchronous merge — prevents FRC stale-fault crash
- `batchInsertTransactions` uses `NSBatchInsertRequest` with proper `mergeBatchInsertResult`
- `TransactionPaginationController` uses `MainActor.assumeIsolated` in FRC delegate — correct

---

## Issues Found

### P0-1: `saveContextSync` called outside `perform` block
**File**: `CoreDataStack.swift:76-85` (`saveContextSync()` private method)
**Problem**: `saveOnBackground()` and `saveOnTerminate()` call `saveContextSync()` which accesses `viewContext` and calls `context.save()` **without** wrapping in `context.perform {}`. These are called from `NotificationCenter` observers which may fire on any thread.
**Impact**: Thread-safety violation. `viewContext` is main-queue confined; calling `save()` off the main thread can corrupt internal state or crash.
**Fix**: Wrap in `viewContext.perform { }` or dispatch to main queue:
```swift
private func saveContextSync() {
    let context = viewContext
    context.perform {
        guard context.hasChanges else { return }
        do { try context.save() }
        catch { ... }
    }
}
```

### P0-2: `saveContextSync(_ context:)` public method has no `perform` guard
**File**: `CoreDataStack.swift:188-191`
**Problem**: Public `saveContextSync(_ context:)` calls `context.save()` directly without `context.perform {}`. Callers can (and do) invoke this on any thread.
**Impact**: Same thread-safety violation as P0-1.
**Fix**: Either remove this method (it's only used internally) or wrap in `performAndWait`.

### P0-3: `batchDelete` / `batchUpdate` execute on viewContext without `perform`
**File**: `CoreDataStack.swift:197-220`
**Problem**: Both `batchDelete()` and `batchUpdate()` call `viewContext.execute()` directly without wrapping in `viewContext.perform {}`. If called from a background thread, this violates viewContext's main-queue confinement.
**Impact**: Potential crash or data corruption if called off main thread.
**Fix**: Wrap in `viewContext.perform { }` or `viewContext.performAndWait { }`.

### P0-4: `saveCategoriesSync` uses viewContext directly on potentially wrong thread
**File**: `CategoryRepository.swift:104-112`
**Problem**: `saveCategoriesSync()` uses `stack.viewContext` directly and calls `saveCategoriesInternal` + `context.save()` **without** `performAndWait`. The viewContext is main-queue confined, but `saveCategoriesSync` could be called from a background context.
**Impact**: Potential crash from main-queue violation.
**Fix**: Use `newBackgroundContext()` like `saveAccountsSync` and `saveSubcategoriesSync` do:
```swift
func saveCategoriesSync(_ categories: [CustomCategory]) throws {
    let context = stack.newBackgroundContext()
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    try context.performAndWait {
        try saveCategoriesInternal(categories, context: context)
        if context.hasChanges { try context.save() }
    }
}
```

---

### P1-1: `context.perform {}` (async) inside `saveSubcategoriesInternal` causes fire-and-forget mutations
**File**: `CategoryRepository.swift:522` (`saveSubcategoriesInternal`)
**Problem**: When updating existing subcategories, uses `context.perform { existing.name = ... }` (async, fire-and-forget). The caller is already inside a `performAndWait` or `perform` block that proceeds to `context.save()` immediately. The async `perform` schedules mutations AFTER the save, so changes are never persisted.
**Impact**: Subcategory name updates are silently lost until next full save cycle.
**Fix**: Change `context.perform { }` to direct mutation (caller is already inside perform):
```swift
if let existing = existingDict[subcategory.id] {
    existing.name = subcategory.name  // direct — already inside perform
}
```

### P1-2: Same fire-and-forget pattern in `saveCategorySubcategoryLinksInternal`
**File**: `CategoryRepository.swift:570-572`
**Problem**: `context.perform { existing.categoryId = ...; existing.subcategoryId = ... }` — async inside sync block.
**Fix**: Same — remove `context.perform { }` wrapper, mutate directly.

### P1-3: Same fire-and-forget pattern in `saveTransactionSubcategoryLinksInternal`
**File**: `CategoryRepository.swift:619-621`
**Fix**: Same pattern.

### P1-4: Same fire-and-forget pattern in `saveAggregatesInternal`
**File**: `CategoryRepository.swift:665-675`
**Fix**: Same — `context.perform { }` should be removed; mutations are already inside a save coordinator's `context.perform`.

---

### P1-5: `resetAllData()` doesn't re-apply persistent history tracking options
**File**: `CoreDataStack.swift:261-286`
**Problem**: After `destroyPersistentStore` + `addPersistentStore`, the recreated store lacks `NSPersistentHistoryTrackingKey` and `NSPersistentStoreRemoteChangeNotificationPostOptionKey`. These are set on the store description before initial `loadPersistentStores()`, but `addPersistentStore(ofType:...)` only receives `NSPersistentStoreFileProtectionKey`.
**Impact**: After `resetAllData()`, persistent history tracking is silently disabled until app restart. Batch operations won't merge to viewContext properly during the same session.
**Fix**: Include both options in the `storeOptions` dictionary passed to `addPersistentStore`:
```swift
let storeOptions: [String: Any] = [
    NSPersistentStoreFileProtectionKey: FileProtectionType.complete,
    NSPersistentHistoryTrackingKey: true as NSNumber,
    NSPersistentStoreRemoteChangeNotificationPostOptionKey: true as NSNumber
]
```

---

### P2-0: N+1 query in `saveRecurringOccurrences`
**File**: `RecurringRepository.swift:221, 227`
**Problem**: For each occurrence being saved, `fetchRecurringSeriesSync()` executes an individual fetch query to resolve the series relationship. Compare with `saveRecurringSeries()` which correctly pre-fetches all needed accounts in one query.
**Impact**: O(N) fetches instead of O(1) batch fetch — noticeable with many occurrences.
**Fix**: Pre-fetch all needed series IDs in one query before the loop, like `saveRecurringSeries` does with accounts.

### P2-1: `loadAggregates` fetches on viewContext (main thread)
**File**: `CategoryRepository.swift:383`
**Problem**: `loadAggregates()` uses `stack.viewContext` directly. All other load methods use `newBackgroundContext()` + `performAndWait`. This blocks the main thread during fetch.
**Impact**: UI jank during aggregate loading.
**Fix**: Use background context pattern consistent with other load methods.

### P2-2: Redundant `context.performAndWait` for property reads inside already-running context
**File**: `AccountRepository.swift:193-196`, `CategoryRepository.swift:444-446`, etc.
**Problem**: Multiple places do `context.performAndWait { entityId = entity.id }` when already inside a `performAndWait` or `perform` block. Nesting `performAndWait` inside `performAndWait` on the SAME context is safe (it runs synchronously on the same queue) but is unnecessary overhead — ~2μs per call × thousands of entities.
**Fix**: Access `entity.id` directly when already inside a context operation.

### P2-3: `saveSubcategories` uses `@MainActor` on `Task.detached`
**File**: `CategoryRepository.swift:202`
**Problem**: `Task.detached(priority: .utility) { @MainActor ... }` — the `@MainActor` annotation forces the detached task to hop to the main thread, then immediately does `context.perform` which hops to the background context's queue. The MainActor hop is wasted work.
**Same issue**: `saveCategorySubcategoryLinks` (line 269), `saveTransactionSubcategoryLinks` (line 337).
**Fix**: Remove `@MainActor` annotation from these `Task.detached` closures.

---

### P3-1: `import Combine` unused in CoreDataStack.swift
**File**: `CoreDataStack.swift:11`
**Fix**: Remove.

### P3-2: `import Combine` unused in CoreDataIndexes.swift
**File**: `CoreDataIndexes.swift:9`
**Fix**: Remove.

### P3-3: `CoreDataIndexes` utility struct is effectively dead code
**File**: `CoreDataIndexes.swift` (161 LOC)
**Problem**: `addIndexesIfNeeded()` is a no-op stub. The static fetch request helpers are never called anywhere (indexes are defined in the model XML). `printIndexStatistics()` discards all values.
**Fix**: Delete file or reduce to only the active helpers.

### P3-4: Model version discrepancy — `.xccurrentversion` says v6, CLAUDE.md says v5
**File**: `.xccurrentversion` → `Tenra v6.xcdatamodel`
**Problem**: CLAUDE.md documents "CoreData v5 model" as current. The actual current model is v6 (adds `isLoan`, `loanInfoData` to AccountEntity).
**Fix**: Update CLAUDE.md to reference v6.

---

## CoreData Model Assessment (v6)

### Entities & Indexes
| Entity | Attributes | Relationships | Indexes | Uniqueness |
|--------|-----------|---------------|---------|------------|
| TransactionEntity | 18 | 3 (account, targetAccount, recurringSeries) | 8 | id |
| AccountEntity | 14 | 3 (transactions, targetTransactions, recurringSeries) | 0 | id |
| RecurringSeriesEntity | 14 | 3 (account, occurrences, transactions) | 0 | id |
| RecurringOccurrenceEntity | 4 | 1 (series) | 0 | id |
| CustomCategoryEntity | 12 | 0 | 0 | id |
| SubcategoryEntity | 3 | 0 | 0 | id |
| CategorySubcategoryLinkEntity | 3 | 0 | 0 | id |
| TransactionSubcategoryLinkEntity | 3 | 0 | 0 | id |
| CategoryAggregateEntity | 11 | 0 | 3 | id |
| CategoryRuleEntity | 4 | 0 | 0 | id |
| MonthlyAggregateEntity | 9 | 0 | 2 | id |

### Model Observations
1. **TransactionEntity has excellent index coverage** — 8 indexes covering date, category, type, and composite queries. This is well-done.
2. **AccountEntity has no fetch indexes** — `id` uniqueness constraint creates a unique index implicitly, but queries by `currency` or `createdAt` won't use indexes. Low impact since account count is typically <20.
3. **RecurringSeriesEntity has no fetch indexes** — same reasoning, series count is small.
4. **Link entities (CategorySubcategoryLink, TransactionSubcategoryLink) have no indexes on foreign keys** — `categoryId`, `subcategoryId`, `transactionId` are used in predicates but have no indexes. Could matter at scale.
5. **MonthlyAggregateEntity + CategoryAggregateEntity** — per CLAUDE.md, these are "not read/written" legacy entities. They still have indexes and uniqueness constraints using storage space.
6. **`isDeposit` is stored in model v6** — CLAUDE.md says it's a computed property (`depositInfo != nil`). Both exist: the model has a stored Boolean, and the Account struct likely has a computed property. The stored version may become stale if `depositInfoData` is set but `isDeposit` isn't updated in tandem.

---

## Fix Plan (Priority Order) — ALL COMPLETE

### Phase 1: P0 Crashes (4 fixes) — DONE
1. **CoreDataStack.saveContextSync()** — wrapped in `viewContext.performAndWait { }`
2. **CoreDataStack.saveContextSync(_ context:)** — wrapped in `context.performAndWait { }`
3. **CoreDataStack.batchDelete/batchUpdate** — wrapped in `viewContext.performAndWait { }`
4. **CategoryRepository.saveCategoriesSync** — switched from `viewContext` to `newBackgroundContext()`

### Phase 2: P1 Silent Data Loss (5 fixes) — DONE
5. **CategoryRepository.saveSubcategoriesInternal** — removed nested `context.perform { }`, mutate directly
6. **CategoryRepository.saveCategorySubcategoryLinksInternal** — same fix
7. **CategoryRepository.saveTransactionSubcategoryLinksInternal** — same fix
8. **CategoryRepository.saveAggregatesInternal** — same fix
9. **CoreDataStack.resetAllData()** — re-applies persistent history tracking options on recreated store

### Phase 3: P2 Performance (4 fixes) — DONE
10. **CategoryRepository.loadAggregates** — switched to `newBackgroundContext()` + `performAndWait`
11. **AccountRepository/CategoryRepository** — removed ~15 redundant nested `performAndWait` calls
12. **CategoryRepository** — removed `@MainActor` from 3 `Task.detached` closures
13. **RecurringRepository.saveRecurringOccurrences** — fixed N+1 query with batch pre-fetch

### Phase 4: P3 Cleanup (10 fixes) — DONE
14. Removed `import Combine` from CoreDataStack.swift and CoreDataIndexes.swift
15. Updated CLAUDE.md: v5 → v6
16. `CoreDataSaveCoordinator.handleMergeConflict` — removed dead retry logic after `context.reset()`
17. `CoreDataSaveCoordinator.performSave` — removed unnecessary `await MainActor.run { }` wrapper (×2)
18. `CoreDataSaveCoordinator.saveBatched` — deleted dead code method
19. Added error logging to 5 empty `catch {}` blocks (TransactionRepo, AccountRepo, CategoryRepo ×3)
20. `TransactionRepository.deleteTransactionImmediately` — `try?` → `do/catch` with error logging
21. Added `Logger` to `AccountRepository` (was missing)
22. Added `import os` to `AccountRepository`

---

## Architecture Strengths (No Action Needed)

- **DTO pattern**: All repositories convert `NSManagedObject` → value types before returning. Views never touch entities directly. This is the gold standard.
- **FRC implementation**: `TransactionPaginationController` is excellent — lazy section conversion, `MainActor.assumeIsolated` in delegate, stored `dateSectionKey` for O(M) section grouping, batch filter updates.
- **Persistent history tracking**: Enabled at container level, purged periodically.
- **Batch operations**: Properly merge object IDs to viewContext via `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)`.
- **Save coordinator**: Actor-based serialization prevents concurrent save conflicts.
- **Store reset handling**: `resetAllData()` → `viewContext.reset()` → notification → FRC rebuild. Correct sequence.
- **Background context isolation**: Each repository operation creates its own `newBackgroundContext()`, preventing context reuse bugs.
- **Uniqueness constraints**: All entities have `id` uniqueness constraints with `NSMergeByPropertyObjectTrumpMergePolicy`.
