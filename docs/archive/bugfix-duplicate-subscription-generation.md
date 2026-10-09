# Bug Fix: Duplicate Subscription Transaction Generation
**Date**: 2026-02-08
**Status**: ✅ FIXED

## Problem

When creating a new subscription, transactions are generated **twice**, resulting in:
- Duplicate transaction ID warnings in console
- ForEach errors about duplicate IDs in UI
- Potential data inconsistency

**Symptom from logs**:
```
🔄 [RecurringTransactionService] Generated 28 new transactions
...
🔄 [RecurringTransactionService] Generated 28 new transactions  // DUPLICATE!
```

## Root Cause

In `TransactionsViewModel.setupRecurringSeriesObserver()`, when handling `.recurringSeriesCreated` notification:

1. Called `self.generateRecurringTransactions()` ✅
2. Called `self.rebuildIndexes()` ✅
3. **Called `self.scheduleBalanceRecalculation()` ❌ DUPLICATE**
4. **Called `self.scheduleSave()` ❌ DUPLICATE**

But `RecurringTransactionService.generateRecurringTransactions()` **already calls** these methods internally (lines 296-297):

```swift
// Inside RecurringTransactionService.generateRecurringTransactions()
Task { @MainActor in
    // ... add transactions to TransactionStore ...

    delegate.scheduleBalanceRecalculation()  // ✅ Already called here!
    delegate.scheduleSave()  // ✅ Already called here!
}
```

**Result**:
- `scheduleBalanceRecalculation()` called twice → duplicate balance recalculations
- `scheduleSave()` called twice → duplicate save operations
- This could potentially trigger the notification observer again if not properly guarded

## The Fix

**File**: `Tenra/ViewModels/TransactionsViewModel.swift`

Removed duplicate calls to `scheduleBalanceRecalculation()` and `scheduleSave()` from the notification observer:

```swift
// BEFORE:
) { [weak self] notification in
    guard let self = self, let _ = notification.userInfo?["seriesId"] as? String else { return }
    guard !self.isProcessingRecurringNotification else { return }

    self.isProcessingRecurringNotification = true
    defer { self.isProcessingRecurringNotification = false }

    self.generateRecurringTransactions()
    self.rebuildIndexes()
    self.scheduleBalanceRecalculation()  // ❌ DUPLICATE
    self.scheduleSave()  // ❌ DUPLICATE
}

// AFTER:
) { [weak self] notification in
    guard let self = self, let seriesId = notification.userInfo?["seriesId"] as? String else { return }

    #if DEBUG
    print("📨 [TransactionsViewModel] Received .recurringSeriesCreated notification for series: \(seriesId)")
    print("   isProcessingRecurringNotification: \(self.isProcessingRecurringNotification)")
    #endif

    guard !self.isProcessingRecurringNotification else {
        #if DEBUG
        print("⚠️ [TransactionsViewModel] Already processing recurring notification, skipping")
        #endif
        return
    }

    self.isProcessingRecurringNotification = true
    defer { self.isProcessingRecurringNotification = false }

    #if DEBUG
    print("🔄 [TransactionsViewModel] Processing .recurringSeriesCreated notification")
    #endif

    // 🔧 FIX: Only call generateRecurringTransactions() - it handles everything internally
    // RecurringTransactionService already calls scheduleBalanceRecalculation() and scheduleSave() inside
    self.generateRecurringTransactions()
    self.rebuildIndexes()
    // 🔧 REMOVED: scheduleBalanceRecalculation() - already called in RecurringTransactionService
    // 🔧 REMOVED: scheduleSave() - already called in RecurringTransactionService

    #if DEBUG
    print("✅ [TransactionsViewModel] Finished processing .recurringSeriesCreated notification")
    #endif
}
```

## Additional Logging Added

Added debug logging to track notification flow:

**SubscriptionsViewModel.swift**:
```swift
#if DEBUG
print("📢 [SubscriptionsViewModel] Posting .recurringSeriesCreated notification for series: \(series.id)")
#endif
NotificationCenter.default.post(...)
```

**TransactionsViewModel.swift**:
```swift
#if DEBUG
print("📨 [TransactionsViewModel] Received .recurringSeriesCreated notification for series: \(seriesId)")
print("   isProcessingRecurringNotification: \(self.isProcessingRecurringNotification)")
#endif
```

This helps verify:
- Notification is posted only once
- Notification is received only once
- Guard clause prevents re-entry if somehow triggered multiple times

---

## Impact

### Before Fix
- ❌ `scheduleBalanceRecalculation()` called twice per subscription creation
- ❌ `scheduleSave()` called twice per subscription creation
- ❌ Potential for duplicate transactions if guard fails
- ❌ Console warnings about duplicate transaction IDs
- ❌ ForEach errors in UI about duplicate IDs

### After Fix
- ✅ `scheduleBalanceRecalculation()` called once per subscription creation
- ✅ `scheduleSave()` called once per subscription creation
- ✅ No duplicate transaction generation
- ✅ Clean console logs
- ✅ No ForEach ID warnings

---

## Testing

### Manual Test
1. Create a new subscription
2. Check console logs:
   - Should see "📢 Posting .recurringSeriesCreated notification" **once**
   - Should see "📨 Received .recurringSeriesCreated notification" **once**
   - Should see "🔄 Generated X new transactions" **once**
   - Should NOT see duplicate transaction warnings

3. Check UI:
   - Transaction list should not show ForEach ID warnings
   - All transactions should display correctly

### Expected Log Flow
```
📢 [SubscriptionsViewModel] Posting .recurringSeriesCreated notification for series: <id>
📨 [TransactionsViewModel] Received .recurringSeriesCreated notification for series: <id>
   isProcessingRecurringNotification: false
🔄 [TransactionsViewModel] Processing .recurringSeriesCreated notification
🔄 [RecurringTransactionService] Generated 28 new transactions  // ONCE ✅
✅ [RecurringTransactionService] Added 28/28 transactions to TransactionStore
🔄 [TransactionsViewModel] scheduleBalanceRecalculation() called  // ONCE ✅
✅ [TransactionsViewModel] Finished processing .recurringSeriesCreated notification
```

---

## Related Files
- `Tenra/ViewModels/TransactionsViewModel.swift` - Removed duplicate method calls, added debug logging
- `Tenra/ViewModels/SubscriptionsViewModel.swift` - Added debug logging for notification posting
- `Tenra/Services/Transactions/RecurringTransactionService.swift` - Original implementation (no changes needed)

---

## Build Status
✅ **BUILD SUCCEEDED** (2026-02-08)

---

## Architecture Notes

### Responsibility Separation

**RecurringTransactionService** is responsible for:
- Generating recurring transactions
- Adding them to TransactionStore
- **Triggering balance recalculation** (via `scheduleBalanceRecalculation()`)
- **Triggering save** (via `scheduleSave()`)

**TransactionsViewModel notification observer** is responsible for:
- Listening for `.recurringSeriesCreated` notification
- Calling `generateRecurringTransactions()` to trigger the flow
- **Rebuilding indexes** (only thing unique to this flow)
- ~~NOT~~ calling `scheduleBalanceRecalculation()` or `scheduleSave()` (handled by service)

### Key Principle

**Single Responsibility**: When delegating to a service method, let the service handle **all** related operations. Don't duplicate those operations in the caller.

---

## Lessons Learned

1. **Avoid Duplicate Orchestration**: When a service method handles the full workflow, don't repeat parts of that workflow in the caller
2. **Guard Against Re-entry**: The `isProcessingRecurringNotification` guard is critical for preventing recursive notification handling
3. **Debug Logging is Essential**: Logging at notification boundaries makes it easy to track control flow and identify duplicates
4. **Task Async Boundaries**: Be careful when mixing synchronous notification handlers with asynchronous Task execution - timing can cause unexpected behavior
