# UI Refresh Trigger Fix

**Date:** 2026-02-01
**Status:** ✅ FIXED
**Related:** aggregate-cache-rebuild-fix.md

## Problem

After aggregate cache rebuild on app startup, the category expense totals were not displaying in the UI (showed 0.00) even though the aggregate cache was successfully rebuilt with all data.

### Root Cause Analysis

The issue was in the notification mechanism used to trigger UI updates after aggregate cache rebuild:

1. **Initial Approach Failed:**
   ```swift
   func notifyDataChanged() {
       allTransactions = Array(allTransactions)  // Create new array
   }
   ```

2. **Why It Failed:**
   - QuickAddCoordinator observes `$allTransactions` via Combine
   - But it uses `.map { $0.count }.removeDuplicates()` to optimize
   - When aggregate rebuild completes, transaction count doesn't change (19253 → 19253)
   - Even though we created a new array instance, the mapped count is identical
   - `.removeDuplicates()` filters it out as a duplicate value
   - Combine publisher never fires
   - UI never updates

3. **Verified by Logs:**
   ```
   ✅ [CategoryAggregateCache] Cache rebuilt: isLoaded=true, keys=6850
   ✅ [CacheCoordinator] Aggregate rebuild complete
   🔄 [TransactionStorageCoordinator] Triggered UI update after aggregate rebuild
   [NO COMBINE PUBLISHER TRIGGER - SILENT FAILURE]
   ```

   But when user manually adds a transaction:
   ```
   🔔 [QuickAddCoordinator] Combine publisher triggered: Transactions: 19254
   📊 [TransactionsViewModel] Returning 28 categories, total: 202345175.31 ← WORKS!
   ```

## Solution

Added a dedicated `@Published var dataRefreshTrigger: UUID` that changes whenever we need to force a UI refresh, independent of transaction count changes.

### Implementation

**1. TransactionsViewModel.swift - Added Trigger Property:**
```swift
@Published var dataRefreshTrigger: UUID = UUID()  // ✅ Trigger for forcing UI updates
```

**2. TransactionsViewModel.swift - Updated notifyDataChanged():**
```swift
func notifyDataChanged() {
    // ✅ CRITICAL FIX: Force @Published to trigger by changing UUID
    // Creating new array doesn't work if count doesn't change, because Combine
    // publisher uses .map { $0.count }.removeDuplicates() which filters it out
    // Instead, we change a dedicated trigger UUID that Combine observes
    dataRefreshTrigger = UUID()

    #if DEBUG
    print("🔔 [TransactionsViewModel] notifyDataChanged() - triggered dataRefreshTrigger")
    #endif
}
```

**3. QuickAddCoordinator.swift - Observe Trigger:**
```swift
private func setupBindings() {
    Publishers.CombineLatest(
        Publishers.CombineLatest4(
            transactionsViewModel.$allTransactions
                .map { $0.count }
                .removeDuplicates(),
            categoriesViewModel.$customCategories
                .map { $0.count }
                .removeDuplicates(),
            timeFilterManager.$currentFilter
                .removeDuplicates(),
            transactionsViewModel.$dataRefreshTrigger  // ✅ NEW: Observe refresh trigger
        ),
        Just(()).eraseToAnyPublisher()
    )
    .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
    .sink { [weak self] combined, _ in
        let (transactionCount, categoryCount, filter, trigger) = combined
        #if DEBUG
        print("🔔 [QuickAddCoordinator] Combine publisher triggered:")
        print("   Transactions: \(transactionCount)")
        print("   Categories: \(categoryCount)")
        print("   Filter: \(filter.displayName)")
        print("   Refresh trigger: \(trigger)")
        #endif
        self?.updateCategories()
    }
    .store(in: &cancellables)
}
```

## Why This Works

1. **Independent from Count:** UUID changes every time `notifyDataChanged()` is called, regardless of transaction count
2. **Survives removeDuplicates():** Each UUID is unique, so it always passes through
3. **Minimal Changes:** Only affects the notification mechanism, not the cache logic
4. **Debuggable:** Logs show the trigger UUID for tracing

## Call Flow After Fix

```
App Startup
  ↓
TransactionStorageCoordinator.loadFromStorage()
  ↓
[Loads 19,253 transactions from CoreData]
  ↓
rebuildAggregateCacheAfterImport()
  ↓
CacheCoordinator.rebuildAggregates()
  ↓
[Builds 6,850 aggregates, sets isLoaded=true]
  ↓
notifyDataChanged()
  ↓
dataRefreshTrigger = UUID()  ← NEW UUID
  ↓
Combine Publishers Fire  ✅
  ├─ QuickAddCoordinator.setupBindings() observes $dataRefreshTrigger
  │  ↓
  │  updateCategories()
  │  ↓
  │  [Updates category grid on home screen]
  │
  └─ ContentView.summaryUpdatePublisher observes $dataRefreshTrigger
     ↓
     updateSummary()
     ↓
     [Updates transaction summary card]
  ↓
TransactionsViewModel.categoryExpenses() (uses aggregate cache)
  ↓
[Returns 28 categories with correct totals]
  ↓
UI Updates  ✅
```

## Files Modified

1. **Tenra/ViewModels/TransactionsViewModel.swift**
   - Added `@Published var dataRefreshTrigger: UUID = UUID()`
   - Updated `notifyDataChanged()` to change trigger instead of array

2. **Tenra/Views/Transactions/QuickAddCoordinator.swift**
   - Updated `setupBindings()` to observe `$dataRefreshTrigger`
   - Added trigger UUID to debug logs

3. **Tenra/Views/Home/ContentView.swift**
   - Updated `summaryUpdatePublisher` to observe `$dataRefreshTrigger`
   - Changed from `Publishers.Merge` to `Publishers.Merge3` to include new trigger
   - This ensures home screen updates when aggregate cache rebuilds

## Testing

1. **App Startup:** Category totals should display immediately (not 0.00)
2. **Time Filter Change:** Totals should update instantly when switching filters
3. **Transaction Add/Delete:** Should continue working as before
4. **CSV Import:** Large imports should show totals after rebuild completes

## Related Issues

- Per-filter caching (aggregate-cache-rebuild-fix.md)
- Race condition in cache invalidation
- Empty result caching prevention

## Lessons Learned

1. **Combine Optimization Can Hide Issues:** Using `.removeDuplicates()` on mapped values is good for performance but can prevent necessary updates when the source changes in ways the mapping doesn't capture

2. **Reference vs Value Equality:** Creating a new array (`Array(allTransactions)`) changes the reference but not the mapped value (`count`), so `removeDuplicates()` still filters it

3. **Explicit Triggers Beat Implicit Inference:** Instead of trying to make Combine "detect" the change, adding an explicit trigger property is clearer and more reliable

4. **Debug Logging is Critical:** Without extensive logging showing "aggregate cache rebuilt but no Combine trigger", this would have been much harder to diagnose
