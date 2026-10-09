# Critical Bug Fix: Missing Accounts Synchronization
**Date**: 2026-02-08
**Status**: ✅ FIXED

## Problem

After creating a subscription, all account balances reset to zero. After app restart, balances restore correctly.

## Root Cause Analysis

### Investigation Process

1. **Added debug logging** to track the entire flow from subscription creation to balance recalculation
2. **User provided logs** showing the exact issue:
   ```
   🔄 [RecurringTransactionService] About to recalculate balances...
      📊 Current state:
         - TransactionStore.accounts: 2  ✅
         - delegate.accounts: 0  ⚠️ PROBLEM!

   🔄 [TransactionsViewModel] scheduleBalanceRecalculation() called
      📊 State at recalculation:
         - accounts.count: 0  ⚠️ PROBLEM!

   🔄 [BalanceCoordinator] processRecalculateAll() started
      📊 Processing 0 accounts with 34 transactions  ⚠️
   ```

### The Bug

`AppCoordinator.setupTransactionStoreObserver()` had an observer for `transactionStore.$transactions` that synced transactions to TransactionsViewModel, but was **missing an observer for `transactionStore.$accounts`**.

**Result**:
- TransactionStore had correct accounts (2)
- TransactionsViewModel.accounts was empty (0)
- When balance recalculation was triggered, BalanceCoordinator received 0 accounts
- BalanceCoordinator calculated 0 balances for all accounts
- UI showed all balances as 0.00

### Why Did It Work After Restart?

On app restart:
1. `AppCoordinator.initialize()` loads data from TransactionStore
2. Accounts are explicitly synced: `accountsViewModel.accounts = transactionStore.accounts`
3. Balance recalculation runs with correct accounts
4. Balances display correctly

But during runtime (after subscription creation):
1. Subscription creates new transactions → added to TransactionStore
2. TransactionStore triggers observer → transactions synced to TransactionsViewModel ✅
3. Balance recalculation is called
4. BUT accounts were never synced from TransactionStore → TransactionsViewModel.accounts = 0 ❌

---

## The Fix

**File**: `Tenra/ViewModels/AppCoordinator.swift`

Added observer for `transactionStore.$accounts` in `setupTransactionStoreObserver()`:

```swift
// 🔧 CRITICAL FIX 2026-02-08: Sync accounts from TransactionStore to TransactionsViewModel
// When TransactionStore updates accounts, sync them to TransactionsViewModel.accounts
// This fixes the bug where balance recalculation runs with 0 accounts after subscription creation
transactionStore.$accounts
    .sink { [weak self] updatedAccounts in
        guard let self = self else { return }

        #if DEBUG
        print("🔄 [AppCoordinator] TransactionStore accounts updated: \(updatedAccounts.count) accounts")
        #endif

        // 🔧 CRITICAL: Sync accounts to TransactionsViewModel
        // This ensures scheduleBalanceRecalculation() has correct accounts
        self.transactionsViewModel.accounts = Array(updatedAccounts)

        // Trigger UI refresh
        self.objectWillChange.send()

        #if DEBUG
        print("✅ [AppCoordinator] Synced accounts to TransactionsViewModel")
        #endif
    }
    .store(in: &cancellables)
```

---

## Impact

### Before Fix
- ❌ Account balances reset to zero after creating subscription
- ❌ User must restart app to see correct balances
- ❌ Poor UX - looks like data loss

### After Fix
- ✅ Account balances remain correct after creating subscription
- ✅ Balance recalculation runs with correct accounts
- ✅ No need to restart app
- ✅ Proper Single Source of Truth pattern maintained

---

## Architecture Notes

### Single Source of Truth (SSOT) Pattern

The app uses TransactionStore as SSOT for:
- Transactions
- Accounts
- Categories

ViewModels (TransactionsViewModel, AccountsViewModel) **observe** TransactionStore via Combine publishers and receive updates.

**Key Lesson**: When implementing SSOT with observers, ensure ALL relevant data is synced, not just transactions.

### Data Flow (After Fix)

```
TransactionStore (SSOT)
  ├─ $transactions ──> AppCoordinator observer ──> TransactionsViewModel.allTransactions ✅
  └─ $accounts    ──> AppCoordinator observer ──> TransactionsViewModel.accounts ✅

When subscription created:
  1. RecurringTransactionService adds transactions to TransactionStore
  2. TransactionStore.$transactions publishes update
  3. AppCoordinator observer syncs to TransactionsViewModel.allTransactions
  4. TransactionStore.$accounts publishes update (even if unchanged)
  5. AppCoordinator observer syncs to TransactionsViewModel.accounts ✅ NEW!
  6. scheduleBalanceRecalculation() runs with correct accounts
  7. BalanceCoordinator calculates correct balances
```

---

## Testing

### Manual Test
1. Create a new account with initial balance
2. Note the balance (e.g., 50,000)
3. Create a subscription (e.g., -6,000 monthly)
4. **Expected**: Balance should update correctly (e.g., 44,000)
5. **Before fix**: Balance shows 0.00 ❌
6. **After fix**: Balance shows 44,000 ✅

### Log Verification
After fix, logs should show:
```
🔄 [AppCoordinator] TransactionStore accounts updated: 2 accounts
✅ [AppCoordinator] Synced accounts to TransactionsViewModel

🔄 [TransactionsViewModel] scheduleBalanceRecalculation() called
   📊 State at recalculation:
      - accounts.count: 2  ✅ Correct!
      - allTransactions.count: 39

🔄 [BalanceCoordinator] processRecalculateAll() started
   📊 Processing 2 accounts with 39 transactions  ✅ Correct!
```

---

## Related Documentation
- `bugfix-subscription-balance-and-category-display.md` - Full history of all fixes
- `bugfix-subscription-balance-debug-logging.md` - Debug logging that helped identify the issue

---

## Build Status
✅ **BUILD SUCCEEDED** (2026-02-08)

---

## Lessons Learned

1. **Complete Observer Coverage**: When syncing data via observers, ensure ALL related data is synced
2. **Debug Logging is Critical**: Detailed logging at each step made the root cause obvious
3. **Test Runtime vs Restart**: Bugs that disappear on restart often indicate missing runtime synchronization
4. **SSOT Pattern**: Single Source of Truth requires proper observer setup for all published data
