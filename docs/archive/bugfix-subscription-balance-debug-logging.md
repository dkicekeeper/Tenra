# Debug Logging: Subscription Balance Issues
**Date**: 2026-02-08
**Status**: 🔍 INVESTIGATION

## Problem
After creating a subscription, account balances are reset to zero. Need detailed logging to diagnose the issue.

## Debug Logging Added

### 1. RecurringTransactionService.generateRecurringTransactions()
**Location**: Line ~281-295

Added logging for:
- Transaction addition to TransactionStore
- Success/failure counts
- **State before balance recalculation:**
  - TransactionStore.transactions count
  - TransactionStore.accounts count
  - delegate.allTransactions count
  - delegate.accounts count
- Confirmation when balance recalculation is scheduled

**Example output:**
```
✅ [RecurringTransactionService] Added 16/16 transactions to TransactionStore
🔄 [RecurringTransactionService] About to recalculate balances...
   📊 Current state:
      - TransactionStore.transactions: 39
      - TransactionStore.accounts: 2
      - delegate.allTransactions: 39
      - delegate.accounts: 2
✅ [RecurringTransactionService] Balance recalculation scheduled
```

### 2. TransactionsViewModel.scheduleBalanceRecalculation()
**Location**: Line ~577-588

Added logging for:
- When method is called
- State at recalculation time:
  - accounts.count
  - allTransactions.count
  - balanceCoordinator availability
- Parameters passed to coordinator.recalculateAll()
- List of first 3 accounts being processed
- Confirmation when recalculation completes

**Example output:**
```
🔄 [TransactionsViewModel] scheduleBalanceRecalculation() called
   📊 State at recalculation:
      - accounts.count: 2
      - allTransactions.count: 39
      - balanceCoordinator available: true
🔄 [TransactionsViewModel] Calling coordinator.recalculateAll with:
      - 2 accounts
      - 39 transactions
      - Account: Счет (id: E0C2D231-...)
      - Account: Бакс (id: 7770AE2E-...)
✅ [TransactionsViewModel] coordinator.recalculateAll completed
```

### 3. BalanceCoordinator.recalculateAll()
**Location**: Line ~252-268

Added logging for:
- Input parameters (accounts count, transactions count)
- Store state (store.accounts count)
- **Balances BEFORE recalculation** (first 5 accounts)
- **Balances AFTER recalculation** (first 5 accounts)

**Example output:**
```
🔄 [BalanceCoordinator] recalculateAll() called
   📊 Input parameters:
      - accounts: 2
      - transactions: 39
   📊 Store state:
      - store.accounts: 2
   💰 Current balances BEFORE recalculation:
      - Счет: 37231.5
      - Бакс: 995.54
✅ [BalanceCoordinator] Recalculated all balances: 2 accounts
   💰 New balances AFTER recalculation:
      - Счет: 0.0  ⚠️ PROBLEM!
      - Бакс: 0.0  ⚠️ PROBLEM!
```

### 4. BalanceCoordinator.processRecalculateAll()
**Location**: Line ~669-687

Added logging for:
- Processing start
- Transactions hash (for cache key)
- For each account:
  - Account name and ID
  - Initial balance
  - Current balance
  - Calculation mode
  - Whether account found in store

**Example output:**
```
🔄 [BalanceCoordinator] processRecalculateAll() started
   📊 Processing 2 accounts with 39 transactions
   🔑 Transactions hash: 1234567890
   🔍 Processing account: Счет (id: E0C2D231-...)
      - Initial balance: 50000.0
      - Current balance: 37231.5
      - Calculation mode: fromInitialBalance
⚠️ [BalanceCoordinator] Account not found in store: 7770AE2E-...
```

---

## What to Look For in Logs

### Scenario 1: Accounts Missing from Store
If you see:
```
⚠️ [BalanceCoordinator] Account not found in store: <accountId>
```

**Problem**: BalanceCoordinator's internal store doesn't have the account
**Possible causes**:
- Accounts not registered with BalanceCoordinator
- Store was cleared/reset
- Race condition during initialization

### Scenario 2: Empty Transactions
If you see:
```
🔄 [TransactionsViewModel] Calling coordinator.recalculateAll with:
      - 2 accounts
      - 0 transactions  ⚠️
```

**Problem**: allTransactions is empty when recalculating
**Possible causes**:
- Observer from TransactionStore → TransactionsViewModel not fired yet
- Race condition: recalculation happens before transactions sync
- allTransactions was cleared

### Scenario 3: Wrong Transaction Count
If transactions count in TransactionStore differs from allTransactions:
```
📊 Current state:
   - TransactionStore.transactions: 39
   - delegate.allTransactions: 7  ⚠️
```

**Problem**: Data not synchronized between stores
**Possible causes**:
- Observer delay
- Multiple stores out of sync
- Cache not invalidated

### Scenario 4: Balance Calculation Returns Zero
If balances change from non-zero to zero:
```
💰 Current balances BEFORE recalculation:
   - Счет: 37231.5
💰 New balances AFTER recalculation:
   - Счет: 0.0  ⚠️
```

**Problem**: Balance calculation is incorrect
**Possible causes**:
- Initial balance lost/reset
- Calculation mode changed
- Transactions not matching account
- Empty transactions array used for calculation

---

## Testing Instructions

1. **Clean start**: Delete app and reinstall
2. **Create accounts**: Add 1-2 accounts with initial balances
3. **Note balances**: Record the initial balances
4. **Create subscription**: Add a new subscription (with or without account)
5. **Check logs**: Look for the patterns above
6. **Check UI**: Verify if balances are shown correctly
7. **Restart app**: Check if balances restore after restart

---

## Expected Log Flow (Successful Case)

```
🔄 [RecurringTransactionService] Generated 16 new transactions
✅ [RecurringTransactionService] TransactionStore available, adding transactions...
✅ [RecurringTransactionService] Added 16/16 transactions to TransactionStore
🔄 [RecurringTransactionService] About to recalculate balances...
   📊 Current state:
      - TransactionStore.transactions: 39
      - TransactionStore.accounts: 2
      - delegate.allTransactions: 39  ✅ Same count
      - delegate.accounts: 2  ✅ Same count
✅ [RecurringTransactionService] Balance recalculation scheduled

🔄 [TransactionsViewModel] scheduleBalanceRecalculation() called
   📊 State at recalculation:
      - accounts.count: 2  ✅
      - allTransactions.count: 39  ✅
      - balanceCoordinator available: true  ✅

🔄 [BalanceCoordinator] recalculateAll() called
   📊 Input parameters:
      - accounts: 2  ✅
      - transactions: 39  ✅
   💰 Current balances BEFORE recalculation:
      - Счет: 37231.5
      - Бакс: 995.54

🔄 [BalanceCoordinator] processRecalculateAll() started
   🔍 Processing account: Счет (id: E0C2D231-...)
      - Initial balance: 50000.0  ✅ Not zero
      - Current balance: 37231.5  ✅ Correct
   🔍 Processing account: Бакс (id: 7770AE2E-...)
      - Initial balance: 1000.0  ✅ Not zero
      - Current balance: 995.54  ✅ Correct

✅ [BalanceCoordinator] Recalculated all balances: 2 accounts
   💰 New balances AFTER recalculation:
      - Счет: 31231.5  ✅ Changed by subscription amount
      - Бакс: 995.54  ✅ Unchanged (no subscription)
```

---

## Files Modified
- `Tenra/Services/Transactions/RecurringTransactionService.swift`
- `Tenra/ViewModels/TransactionsViewModel.swift`
- `Tenra/Services/Balance/BalanceCoordinator.swift`

---

## Next Steps
1. Run app with these logs
2. Create a subscription
3. Share the full console output
4. Identify which scenario matches the logs
5. Implement targeted fix based on findings
