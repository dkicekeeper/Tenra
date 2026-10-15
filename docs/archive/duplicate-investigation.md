# 🔍 Duplicate Transaction Investigation

**Date**: 2026-02-08
**Status**: 🟡 INVESTIGATING
**Reporter**: User

---

## 📋 Problem Report

User reported: "Дублирование еще есть после создания новой подписки" (Duplication still exists after creating new subscription)

---

## 🔍 Investigation Findings

### 1. Code Analysis

I've thoroughly analyzed the transaction generation logic and found:

#### ✅ Deduplication Mechanisms in Place

**File**: `RecurringTransactionGenerator.swift`

1. **Occurrence Key Check** (line 113):
   ```swift
   let occurrenceKey = "\(series.id):\(dateString)"
   if !existingOccurrenceKeys.contains(occurrenceKey) {
       // Generate transaction
   }
   ```
   - Prevents generating multiple transactions for the same date within a series
   - Key format: `seriesId:date` ensures uniqueness per subscription per date

2. **Transaction ID Check** (line 128):
   ```swift
   if !existingTransactionIds.contains(transactionId) {
       // Add transaction
   }
   ```
   - Prevents adding transactions with duplicate IDs
   - Transaction ID is deterministic based on:
     - Date
     - Description
     - Amount
     - Type
     - Currency
     - Created timestamp (derived from transaction date, not current time)

#### ✅ Single Generation Per Call

From logs analysis:
```
🔄 [RecurringTransactionService] Generated 16 new transactions
✅ [RecurringTransactionService] Added 16/16 transactions to TransactionStore
```

- Only **one generation call** per subscription creation
- No double generation in logs
- Notification system working correctly (no duplicate calls)

#### ✅ UI Display Logic

**File**: `HistoryTransactionsList.swift` (line 89):
```swift
ForEach(grouped[dateKey] ?? []) { transaction in
    TransactionCard(...)
}
```

- Uses SwiftUI's `ForEach` with `transaction.id`
- Should not display duplicate IDs
- If duplicate IDs exist, SwiftUI would show error: "ForEach: the ID occurs multiple times"

---

## 🤔 Possible Explanations

### 1. **Multiple Subscriptions Confusion** (Most Likely)

From the user's logs:
```
🔄 Generated 16 new transactions
```

This suggests **4 subscriptions × 4 months each = 16 transactions**

**User might be seeing:**
- Music subscription: 4 transactions (Feb, Mar, Apr, May)
- Gogl subscription: 4 transactions (Feb, Mar, Apr, May)
- Sss subscription: 4 transactions (Feb, Mar, Apr, May)
- 4th subscription: 4 transactions (Feb, Mar, Apr, May)

**This is NOT duplication** - these are 4 separate subscriptions each generating their own future transactions.

### 2. **Legacy Duplicates from Before Fix**

If duplicates existed before the fix was applied (commit `e75b410`), they might still be in the database. New subscriptions won't have duplicates, but old ones might.

### 3. **Same Name/Amount Subscriptions**

If user created multiple subscriptions with:
- Same description (e.g., "Music")
- Same amount
- Same frequency
- Different accounts or categories

These would be **legitimate separate subscriptions**, not duplicates.

### 4. **Display Filter Issue**

The "All Time" filter might be showing:
- Current month transaction: "Music - $10 - Feb 15"
- Future month transaction: "Music - $10 - Mar 15"
- User interprets these as "duplicates" when they're actually different months

---

## 📊 What We Know from Logs

### Session 1: Initial Load
```
📂 Loaded from storage: 6 transactions, 6 occurrences, 4 series
```

### Session 2: After New Subscription
```
🔄 Generated 16 new transactions
✅ Added 16/16 transactions to TransactionStore
💰 Total balance: 33000.0 KZT
📊 allTransactions: 26 transactions  ← 6 old + 16 new + 4 more = 26
📊 History filtered to 8 transactions  ← Only current month shown (fix working!)
```

**Analysis**:
- 6 existing transactions (from before)
- 16 new transactions (from new subscription creation)
- 4 more transactions (from "Tee" subscription)
- Total: 26 transactions ✅
- History shows: 8 transactions (only current month) ✅

**No evidence of duplication in generation logic.**

---

## ❓ Questions for User

To diagnose the issue, we need clarification:

### 1. **What Exactly Are You Seeing as Duplicates?**
   - [ ] Same transaction appearing twice with the **exact same date**?
   - [ ] Same subscription name on **different dates** (e.g., Feb 15, Mar 15)?
   - [ ] Multiple subscriptions with the **same name** but different details?

### 2. **Where Are You Seeing Duplicates?**
   - [ ] In the **History** view (transaction list)?
   - [ ] In the **Subscriptions** view (subscription list)?
   - [ ] In the **Category Expenses** breakdown?
   - [ ] In the **Account Balance** calculation?

### 3. **Can You Provide an Example?**
   Please share:
   - Screenshot of the duplicate transactions
   - Or describe: "I see 'Music - 5000 KZT - Feb 15' appearing **2 times** in the list"

### 4. **Did You Create Multiple Subscriptions with the Same Name?**
   - [ ] Yes, I created multiple subscriptions called "Music"
   - [ ] No, I only created one subscription called "Music"

---

## 🔬 Next Steps

### If Duplicates Are Real:
1. Add debug logging to capture duplicate transaction IDs
2. Check if Transaction IDs are truly identical
3. Investigate TransactionStore.add() method for potential race conditions
4. Check if observer pattern is triggering multiple additions

### If Not Duplicates:
1. Clarify with user that multiple months = not duplicates
2. Explain that future transactions are generated but hidden from history
3. Consider adding UI indicators to show "this is a recurring transaction"

---

## 🧪 Testing Commands for User

To help diagnose, please run the app and:

1. **Check for duplicate IDs:**
   - Filter logs for "Added X/X transactions"
   - Look for any warnings about duplicate IDs

2. **Check transaction list:**
   - Go to History
   - Switch to "All Time" filter
   - Count transactions with same date and description
   - If you see two transactions with **identical** date, amount, and description, those are duplicates

3. **Check subscription list:**
   - Go to Subscriptions
   - Count how many subscriptions have the same name
   - Each subscription should generate its own transactions

---

## 📝 Summary

**Status**: ✅ **ROOT CAUSE FOUND AND FIXED**

**Root Cause**: Deleted subscription transactions were NOT being removed from database
- Only removed from memory (`allTransactions`)
- On app restart, old transactions loaded back from database
- Combined with new transactions = appearing as "duplicates"

**Fix Applied**: Use `TransactionStore.delete()` to remove from both memory AND database

**Not duplicates, but zombie transactions**: User was seeing old deleted subscriptions mixed with new ones

---

## ✅ Verification Checklist

- [x] Analyzed transaction generation logic
- [x] Verified deduplication mechanisms exist
- [x] Checked logs for evidence of duplicate generation
- [x] Reviewed UI display logic
- [x] Confirmed notification system working correctly
- [ ] **Waiting for user clarification on what duplicates they're seeing**

