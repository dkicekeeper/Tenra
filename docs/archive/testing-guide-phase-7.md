# Testing Guide - Phase 7 UI Migration
## Manual Testing Checklist for TransactionStore Operations

> **Цель:** Verify that Add, Update, Delete operations work correctly through TransactionStore
> **Статус:** Ready for testing
> **Дата:** 2026-02-05

---

## 🧪 Pre-requisites

### Build Status
- [x] Build succeeds: `xcodebuild -scheme Tenra build`
- [x] Unit tests pass: 18/18 TransactionStore tests
- [ ] No console errors on app launch

### Environment Setup
1. Launch Tenra in iOS Simulator
2. Ensure you have at least 1 account created
3. Ensure you have at least 1 custom category created
4. Keep Console.app open to monitor debug output

---

## ✅ Test Case 1: Add Transaction (QuickAdd Flow)

### Goal
Verify that creating a transaction through QuickAdd uses TransactionStore correctly.

### Steps
1. **Open QuickAdd**
   - Tap on "Add" tab or QuickAdd button
   - Should see category grid

2. **Select Category**
   - Tap on any category (e.g., "Food", "Transport")
   - Should open AddTransactionModal

3. **Fill Form**
   - Enter amount: `100`
   - Select account from dropdown
   - Optionally: add description "Test transaction"
   - Optionally: select subcategories

4. **Save Transaction**
   - Tap checkmark button ✓
   - OR: Tap date button at bottom and select date

### Expected Results
- ✅ Modal dismisses immediately
- ✅ Success haptic feedback
- ✅ Transaction appears in transaction list
- ✅ Transaction saved to CoreData (persists after app restart)
- ✅ **Console output:** `✅ [TransactionStore] Added: ...`
- ✅ **NEW Phase 7.1:** Account balance updates automatically

### Error Testing
1. **Invalid Amount**
   - Leave amount empty or enter `0`
   - Tap save
   - **Expected:** Error message appears, form doesn't close

2. **No Account Selected**
   - Clear account selection
   - Tap save
   - **Expected:** Error message appears

### Debug Verification
Check Console.app for:
```
✅ [TransactionStore] Added: TransactionEvent.added(...)
💾 [TransactionStore] Persisted transactions to repository
🔄 [BalanceCoordinator] Recalculating balances for accounts: [...]
```

---

## ✅ Test Case 2: Update Transaction (Edit Flow)

### Goal
Verify that updating a transaction through EditTransactionView uses TransactionStore correctly.

### Steps
1. **Find Transaction**
   - Navigate to transaction list (History or Home)
   - Locate the transaction created in Test Case 1

2. **Open Edit Modal**
   - Tap on the transaction card
   - Should open EditTransactionView

3. **Modify Transaction**
   - Change amount from `100` to `150`
   - Change description to "Updated test transaction"
   - Change date if desired

4. **Save Changes**
   - Tap checkmark button ✓

### Expected Results
- ✅ Modal dismisses immediately
- ✅ Success haptic feedback
- ✅ Transaction shows updated values in list
- ✅ Changes persisted to CoreData
- ✅ **Console output:** `✅ [TransactionStore] Updated: ...`
- ✅ **NEW Phase 7.1:** Account balance recalculates (if amount changed)

### Error Testing
1. **Invalid Update**
   - Change amount to `0` or empty
   - Tap save
   - **Expected:** Error alert appears

2. **Network Error Simulation** (if applicable)
   - Try updating with airplane mode on (if app syncs)
   - **Expected:** Error alert with localized message

### Debug Verification
Check Console.app for:
```
✅ [TransactionStore] Updated: TransactionEvent.updated(old: ..., new: ...)
💾 [TransactionStore] Persisted transactions to repository
🔄 [BalanceCoordinator] Recalculating balances for accounts: [...]
```

---

## ✅ Test Case 3: Delete Transaction (Swipe-to-Delete)

### Goal
Verify that deleting a transaction through swipe action uses TransactionStore correctly.

### Steps
1. **Find Transaction**
   - Navigate to transaction list
   - Locate the transaction updated in Test Case 2

2. **Swipe to Delete**
   - Swipe left on the transaction card
   - Should reveal red "Delete" button

3. **Confirm Delete**
   - Tap "Delete" button (trash icon)

### Expected Results
- ✅ Transaction immediately disappears from list
- ✅ Warning haptic feedback on swipe
- ✅ Success haptic on delete
- ✅ Transaction removed from CoreData
- ✅ **Console output:** `✅ [TransactionStore] Deleted: ...`
- ✅ **NEW Phase 7.1:** Account balance adjusts (amount removed from account)

### Error Testing
1. **Delete Non-existent Transaction** (edge case)
   - Manually modify database to create orphan reference
   - Try to delete
   - **Expected:** Error alert appears (if detection implemented)

### Debug Verification
Check Console.app for:
```
✅ [TransactionStore] Deleted: TransactionEvent.deleted(...)
💾 [TransactionStore] Persisted transactions to repository
🔄 [BalanceCoordinator] Recalculating balances for accounts: [...]
```

---

## ✅ Test Case 4: Transfer Operation (Phase 7.4)

### Goal
Verify that transfer operations through AccountActionView use TransactionStore correctly.

### Steps - Regular Account Transfer
1. **Open Account Actions**
   - Navigate to Accounts tab
   - Tap on any account (e.g., "Main Account")
   - Tap on transfer/action button

2. **Select Transfer**
   - Ensure "Transfer" option is selected (should be default)
   - Enter amount: `200`
   - Select target account from dropdown

3. **Fill Details**
   - Optionally: add description "Test transfer"
   - Tap save button

### Expected Results - Regular Transfer
- ✅ Modal dismisses immediately
- ✅ Success haptic feedback
- ✅ Transfer transaction appears in both accounts' history
- ✅ Source account balance decreases
- ✅ Target account balance increases
- ✅ **Console output:** Transfer created via TransactionStore

### Steps - Deposit Transfer (Top-Up)
1. **Open Deposit Account**
   - Navigate to Deposits tab
   - Tap on any deposit
   - Tap "Top Up" button

2. **Enter Amount**
   - Enter amount: `500`
   - Select source account (where funds come from)

3. **Save Transfer**
   - Add description if desired
   - Tap save button

### Expected Results - Deposit Top-Up
- ✅ Deposit balance increases by amount
- ✅ Source account balance decreases
- ✅ Transfer transaction visible in both histories
- ✅ Correct direction (FROM source TO deposit)

### Steps - Deposit Withdrawal
1. **Open Deposit Account**
   - Tap on deposit
   - Tap "Withdraw" button

2. **Enter Amount**
   - Enter amount: `300`
   - Select target account (where funds go)

3. **Save Withdrawal**
   - Add description
   - Tap save button

### Expected Results - Deposit Withdrawal
- ✅ Deposit balance decreases
- ✅ Target account balance increases
- ✅ Transfer transaction created correctly
- ✅ Correct direction (FROM deposit TO target)

### Steps - Income Operation
1. **Open Account Actions**
   - Navigate to regular account
   - Tap action button
   - Switch to "Top Up" tab

2. **Enter Income**
   - Enter amount: `1000`
   - Select income category (e.g., "Salary")
   - Add description

3. **Save Income**
   - Tap save button

### Expected Results - Income
- ✅ Income transaction created
- ✅ Account balance increases
- ✅ Transaction shows in income category
- ✅ Uses TransactionStore.add()

### Currency Conversion Test
1. **Create Cross-Currency Transfer**
   - Source account: KZT
   - Target account: USD
   - Amount: 10000 KZT
   - Save

### Expected Results - Currency
- ✅ Conversion happens automatically
- ✅ Target account receives correct USD amount
- ✅ Exchange rate applied
- ✅ Both amounts stored correctly

### Debug Verification
Check Console.app for:
```
✅ [TransactionStore] Transfer: 200.0 USD from [sourceId] to [targetId]
💾 [TransactionStore] Persisted transactions to repository
🔄 [BalanceCoordinator] Recalculating balances for accounts: [sourceId, targetId]
```

---

## ✅ Test Case 5: Recurring Transactions

### Goal
Verify recurring transactions work with TransactionStore.

### Steps
1. **Create Recurring Transaction**
   - Open QuickAdd
   - Select category
   - Fill form with amount `50`
   - Toggle "Make Recurring" ON
   - Select frequency: "Monthly"
   - Save

2. **Verify Recurring**
   - Check that recurring series was created
   - Transaction should show recurring badge

3. **Edit Recurring**
   - Tap on recurring transaction
   - Change amount to `75`
   - Save
   - **Expected:** Series updated

4. **Stop Recurring**
   - Swipe on recurring transaction
   - Tap "Stop Recurring" button (if available)
   - **Expected:** Future occurrences disabled

### Expected Results
- ✅ Recurring series created
- ✅ Transaction has `recurringSeriesId`
- ✅ Updates propagate to series
- ✅ Can stop recurring series

---

## ✅ Test Case 6: Subcategories

### Goal
Verify subcategory linking works with TransactionStore.

### Steps
1. **Create with Subcategories**
   - Open QuickAdd
   - Select category that has subcategories
   - Select 2-3 subcategories from list
   - Save transaction

2. **Verify Linking**
   - Transaction should show subcategory badges
   - Check CoreData for `transactionSubcategoryLinks`

3. **Edit Subcategories**
   - Edit transaction
   - Remove one subcategory, add another
   - Save
   - **Expected:** Links updated

### Expected Results
- ✅ Subcategories linked correctly
- ✅ Updates work correctly
- ✅ Links persisted to CoreData

---

## ✅ Test Case 7: Multiple Operations

### Goal
Stress test multiple operations in sequence.

### Steps
1. **Rapid Create**
   - Create 5 transactions quickly through QuickAdd
   - Different amounts: 10, 20, 30, 40, 50

2. **Bulk Edit**
   - Edit 3 of the transactions
   - Change amounts and descriptions

3. **Bulk Delete**
   - Delete 2 transactions via swipe

### Expected Results
- ✅ All operations complete successfully
- ✅ No race conditions
- ✅ No duplicate transactions
- ✅ Correct transaction count in list

---

## ✅ Test Case 8: Currency Conversion

### Goal
Verify currency conversion works in add/update operations.

### Steps
1. **Create with Different Currency**
   - Account currency: KZT
   - Transaction currency: USD
   - Amount: 100 USD
   - Save

2. **Verify Conversion**
   - Transaction should show `convertedAmount` in KZT
   - Check console for conversion rate used

3. **Update Currency**
   - Edit transaction
   - Change currency from USD to EUR
   - Amount: 100 EUR
   - Save
   - **Expected:** New conversion applied

### Expected Results
- ✅ Currency conversion happens
- ✅ `convertedAmount` stored correctly
- ✅ Updates recalculate conversion

---

## ✅ Balance Updates - Phase 7.1 COMPLETE

### Balance Integration Status
**Phase 7.1 Implementation:** ✅ Complete (2026-02-05)

**Current Behavior:**
- Creating transaction → balance AUTOMATICALLY updated by TransactionStore
- Updating transaction → balance RECALCULATED by BalanceCoordinator
- Deleting transaction → balance ADJUSTED by BalanceCoordinator
- Console shows: `✅ [TransactionStore] Added/Updated/Deleted: ...` (no more warnings)

**What Changed:**
- TransactionStore now has `balanceCoordinator` dependency
- All CRUD operations call `updateBalances(for:)` after success
- `TransactionEvent.affectedAccounts` identifies which accounts to update
- Asynchronous recalculation via `balanceCoordinator.recalculateAccounts()`

**Verification:**
- After creating transaction → check account balance updates
- After editing amount → verify balance recalculates correctly
- After deleting → verify balance adjusts (amount removed)
- Check that multiple accounts update for transfers

---

## 🐛 Bug Reporting

### If Test Fails
1. **Note the exact steps** to reproduce
2. **Check Console.app** for error messages
3. **Check Xcode console** for stack traces
4. **Create report with:**
   - Test case number
   - Steps to reproduce
   - Expected vs actual result
   - Console output
   - Screenshots if UI issue

### Common Issues

#### Issue: Transaction doesn't save
**Possible Causes:**
- CoreData issue
- Validation error not shown
- TransactionStore not injected via @EnvironmentObject

**Debug:**
- Check console for error
- Verify `@EnvironmentObject var transactionStore` in View
- Check TenraApp.swift has `.environmentObject(coordinator.transactionStore)`

#### Issue: App crashes on operation
**Possible Causes:**
- Force unwrap of optional failed
- MainActor threading issue
- TransactionStore nil

**Debug:**
- Check crash log in Xcode
- Verify all @EnvironmentObject dependencies available
- Check for force unwraps in modified code

#### Issue: Error alert appears unexpectedly
**Possible Causes:**
- Validation error
- Repository error
- TransactionStore error

**Debug:**
- Read error message carefully
- Check console for detailed error
- Verify error is localized

---

## ✅ Success Criteria

### Phase 7.0-7.4 Complete if:
- [ ] All Test Cases 1-4 pass (Add, Update, Delete, Transfer)
- [ ] Test Cases 5-8 pass (Recurring, Subcategories, Multiple ops, Currency)
- [ ] No crashes or unexpected errors
- [ ] Console shows correct TransactionStore debug output
- [ ] Transactions persist after app restart
- [ ] Balances update correctly for all operations

### ✅ Phase 7.1 (Balance) Complete:
- [x] Balance integration implemented
- [x] TransactionStore has balanceCoordinator dependency
- [x] Automatic updates on add/update/delete/transfer
- [ ] Manual testing confirms balances update correctly

### ✅ Phase 7.4 (Transfer) Complete:
- [x] AccountActionView migrated
- [x] Transfer operation uses TransactionStore
- [x] Income operation uses TransactionStore
- [x] Works for regular and deposit accounts
- [ ] Manual testing confirms transfers work correctly

### 🎉 ALL CRUD OPERATIONS MIGRATED:
- [x] Create (Add) - QuickAdd, AccountActionView
- [x] Read - Not needed (uses ViewModel)
- [x] Update - EditTransactionView
- [x] Delete - TransactionCard
- [x] Transfer - AccountActionView

### Ready for Phase 7.5+ (Remaining Views):
- [ ] All critical operations tested
- [ ] No blocking bugs
- [ ] Pattern proven for 4 views

---

## 📊 Test Results Template

```markdown
## Test Results - Phase 7.0-7.3
**Date:** YYYY-MM-DD
**Tester:** Your Name
**Device:** iPhone 17 Simulator / Real Device
**iOS Version:** 26.2

### Test Case 1: Add Transaction
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 2: Update Transaction
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 3: Delete Transaction
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 4: Transfer Operation
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 5: Recurring Transactions
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 6: Subcategories
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 7: Multiple Operations
- [ ] PASS / [ ] FAIL
- Notes:

### Test Case 8: Currency Conversion
- [ ] PASS / [ ] FAIL
- Notes:

### Overall Status
- [ ] All tests passed - Ready for Phase 7.5 (Remaining Views)
- [ ] Some tests failed - See bugs below
- [ ] Critical issues found - Needs fixes

### Bugs Found
1. [Bug description]
   - Severity: Critical / High / Medium / Low
   - Steps to reproduce:
   - Expected:
   - Actual:

### Notes
[Any additional observations]
```

---

**Last Updated:** 2026-02-05 (Phase 7.4 Complete)
**Status:** Ready for Manual Testing
**Coverage:** ALL CRUD operations via TransactionStore (Add, Update, Delete, Transfer) 🎉
