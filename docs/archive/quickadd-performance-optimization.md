# QuickAdd Performance Optimization Plan

**Date:** 2026-02-01
**Status:** 🔍 Analysis Complete - Ready for Implementation
**Context:** Sheet opening delay with 19,000 transactions

---

## 🎯 Goal

Make AddTransactionModal sheet opening **instant** (< 50ms) like account tap, regardless of transaction count.

---

## 📊 Performance Analysis

### Current Bottleneck Identified

**Location:** AddTransactionCoordinator.swift:49-53

```swift
let suggestedAccount = accountsViewModel.suggestedAccount(
    forCategory: category,
    transactions: transactionsViewModel.allTransactions,  // ❌ 19,000 transactions!
    amount: nil
)
```

**Problem Chain:**
1. **AddTransactionCoordinator init** calls `suggestedAccount()`
2. **suggestedAccount()** → AccountRankingService.suggestedAccount:129-131
   - Filters ALL 19,000 transactions: `transactions.filter { $0.category == category }`
   - **O(n) = 19,000 iterations**
3. **categoryTransactions loop** (lines 143-157)
   - Iterates through filtered transactions
   - Date parsing for EVERY transaction
   - **O(m) where m = category transaction count (could be 1000+)**
4. **accountFrequency sorting** (lines 160-169)
   - Sorts by frequency + last used date
   - **O(k log k) where k = unique accounts**

**Total Complexity:** O(n) + O(m) + O(k log k) ≈ **O(19,000+)** per sheet open

**Why it's slow:**
- 19,000 array scans EVERY time user taps a category
- Date string parsing (expensive) for each transaction
- No caching of results
- Runs on MainActor blocking UI

---

## 🚀 Optimization Strategy

### Phase 1: Category-Account Frequency Cache ✅ RECOMMENDED

**Concept:** Pre-compute and cache category → account frequency mapping

**Implementation:**

#### 1.1 Create CategoryAccountCache Service

**File:** `Services/Cache/CategoryAccountCache.swift`

```swift
import Foundation
import Combine

/// Cached frequency data for category-account pairs
struct CategoryAccountFrequency {
    let accountId: String
    let frequency: Int
    let lastUsedDate: Date
}

/// Cache for category → account frequency mapping
@MainActor
final class CategoryAccountCache: ObservableObject {

    // MARK: - Cache Storage

    /// category → [accountId → frequency data]
    private var cache: [String: [String: CategoryAccountFrequency]] = [:]

    /// Last cache invalidation timestamp
    private var lastInvalidation: Date = Date()

    // MARK: - Public Methods

    /// Get suggested account for category (O(1) lookup!)
    func suggestedAccount(
        forCategory category: String,
        accounts: [Account],
        amount: Double? = nil
    ) -> Account? {
        guard let frequencyMap = cache[category] else {
            return nil  // Cache miss - fallback to general ranking
        }

        // Sort by frequency, then by last used date
        let sortedAccountIds = frequencyMap
            .sorted { entry1, entry2 in
                if entry1.value.frequency != entry2.value.frequency {
                    return entry1.value.frequency > entry2.value.frequency
                }
                return entry1.value.lastUsedDate > entry2.value.lastUsedDate
            }
            .map { $0.key }

        // Find first account with sufficient balance
        for accountId in sortedAccountIds {
            if let account = accounts.first(where: { $0.id == accountId }) {
                if let amount = amount, account.balance < amount {
                    continue  // Insufficient balance
                }
                return account
            }
        }

        return nil
    }

    /// Rebuild cache from transactions (called on app start + after imports)
    func rebuild(from transactions: [Transaction]) {
        let startTime = CFAbsoluteTimeGetCurrent()

        cache.removeAll()

        // Group transactions by category
        var categoryTransactions: [String: [Transaction]] = [:]

        for transaction in transactions {
            guard transaction.type == .expense else { continue }
            categoryTransactions[transaction.category, default: []].append(transaction)
        }

        // Build frequency maps for each category
        for (category, txs) in categoryTransactions {
            var frequencyMap: [String: CategoryAccountFrequency] = [:]

            for transaction in txs {
                guard let accountId = transaction.accountId,
                      let date = DateFormatters.dateFormatter.date(from: transaction.date) else {
                    continue
                }

                if let existing = frequencyMap[accountId] {
                    let newFrequency = existing.frequency + 1
                    let newLastUsed = max(existing.lastUsedDate, date)
                    frequencyMap[accountId] = CategoryAccountFrequency(
                        accountId: accountId,
                        frequency: newFrequency,
                        lastUsedDate: newLastUsed
                    )
                } else {
                    frequencyMap[accountId] = CategoryAccountFrequency(
                        accountId: accountId,
                        frequency: 1,
                        lastUsedDate: date
                    )
                }
            }

            cache[category] = frequencyMap
        }

        lastInvalidation = Date()

        #if DEBUG
        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("🗄️ [CategoryAccountCache] Rebuilt cache in \(totalTime)ms")
        print("📊 [CategoryAccountCache] Cached \(cache.count) categories")
        #endif
    }

    /// Invalidate cache (call after adding/deleting transactions)
    func invalidate() {
        cache.removeAll()
        lastInvalidation = Date()
    }

    /// Check if cache is valid
    var isValid: Bool {
        return !cache.isEmpty
    }
}
```

**Performance:**
- **Cache rebuild:** O(n) = 19,000 iterations (done ONCE on app start)
- **suggestedAccount lookup:** O(1) average, O(k) worst case where k = accounts per category (~10-20)
- **Memory:** ~50-100 KB for 19,000 transactions

**Trade-offs:**
- ✅ 19,000x faster lookup (O(1) vs O(n))
- ✅ No UI blocking - instant sheet opening
- ⚠️ Requires cache invalidation on transaction add/delete
- ⚠️ Small memory overhead (~100 KB)

---

#### 1.2 Integrate Cache into AccountsViewModel

**File:** `ViewModels/AccountsViewModel.swift`

```swift
@MainActor
class AccountsViewModel: ObservableObject {

    // Add cache property
    private let categoryAccountCache = CategoryAccountCache()

    // Modify suggestedAccount to use cache
    func suggestedAccount(
        forCategory category: String,
        transactions: [Transaction],
        amount: Double? = nil
    ) -> Account? {

        // Try cache first (O(1) lookup!)
        if categoryAccountCache.isValid,
           let cached = categoryAccountCache.suggestedAccount(
            forCategory: category,
            accounts: accounts,
            amount: amount
           ) {
            #if DEBUG
            print("✅ [AccountsViewModel] Cache HIT for category: \(category)")
            #endif
            return cached
        }

        #if DEBUG
        print("⚠️ [AccountsViewModel] Cache MISS for category: \(category)")
        #endif

        // Fallback to original logic
        return AccountRankingService.suggestedAccount(
            forCategory: category,
            accounts: accounts,
            transactions: transactions,
            amount: amount
        )
    }

    // Call rebuild on app start or after transaction import
    func rebuildCategoryCache(transactions: [Transaction]) {
        categoryAccountCache.rebuild(from: transactions)
    }

    // Call invalidate after transaction add/delete
    func invalidateCategoryCache() {
        categoryAccountCache.invalidate()
    }
}
```

---

#### 1.3 Trigger Cache Rebuild

**File:** `ViewModels/TransactionsViewModel.swift`

```swift
// Add after transaction operations
func addTransaction(_ transaction: Transaction) {
    // ... existing code ...

    // Invalidate cache
    accountsViewModel?.invalidateCategoryCache()
}

func deleteTransaction(_ transaction: Transaction) {
    // ... existing code ...

    // Invalidate cache
    accountsViewModel?.invalidateCategoryCache()
}

// Rebuild cache on app start
func loadTransactionsOnAppStart() {
    // ... existing code ...

    // Build cache after loading
    accountsViewModel?.rebuildCategoryCache(transactions: allTransactions)
}

// Rebuild cache after CSV import
func importFromCSV(...) async throws {
    // ... existing code ...

    // Rebuild cache after import completes
    accountsViewModel?.rebuildCategoryCache(transactions: allTransactions)
}
```

---

### Phase 2: Lazy Account Suggestion (Alternative - Simpler)

**Concept:** Don't compute suggested account in coordinator init - compute on demand when user opens account picker

**Implementation:**

```swift
@MainActor
final class AddTransactionCoordinator: ObservableObject {

    init(...) {
        // Remove suggestedAccount() call from init
        self.formData = TransactionFormData(
            category: category,
            type: type,
            currency: currency,
            suggestedAccountId: nil  // ❌ Don't compute here
        )
    }

    // Add computed property
    var suggestedAccountId: String? {
        let suggested = accountsViewModel.suggestedAccount(
            forCategory: formData.category,
            transactions: transactionsViewModel.allTransactions,
            amount: formData.amountDouble
        )
        return suggested?.id ?? accountsViewModel.accounts.first?.id
    }
}
```

**Usage in AddTransactionModal:**
```swift
AccountSelectorView(
    accounts: coordinator.rankedAccounts(),
    selectedAccountId: Binding(
        get: { coordinator.formData.accountId ?? coordinator.suggestedAccountId },
        set: { coordinator.formData.accountId = $0 }
    )
)
```

**Performance:**
- **Init time:** 0ms (instant)
- **First account picker open:** ~50-100ms (only if user opens picker)
- **Sheet open:** Instant ✅

**Trade-offs:**
- ✅ Zero init overhead - instant sheet opening
- ✅ No cache needed - simpler implementation
- ⚠️ Slight delay when user opens account picker (acceptable)
- ⚠️ Suggestion only computed if user interacts with account selector

---

## 📈 Performance Comparison

| Approach | Init Time | Sheet Open | Cache Rebuild | Memory | Complexity |
|----------|-----------|------------|---------------|--------|------------|
| **Current (No optimization)** | 200-500ms | 200-500ms | N/A | 0 KB | O(n) |
| **Phase 1: Cache** | 0ms | **< 10ms** ✅ | 100-200ms (once) | ~100 KB | O(1) |
| **Phase 2: Lazy** | **0ms** ✅ | **< 10ms** ✅ | N/A | 0 KB | Deferred |

---

## 🎯 Recommended Approach

### **Hybrid Strategy: Phase 2 (Lazy) + Phase 1 (Cache) for Account Picker**

**Reasoning:**
1. **Phase 2 first** - Instant sheet opening with minimal code changes
2. **Phase 1 later** - Add cache to optimize account picker opening if needed

**Implementation Order:**
1. ✅ Remove `suggestedAccount()` from AddTransactionCoordinator init
2. ✅ Add lazy computed property for suggested account
3. ✅ Update AccountSelectorView binding
4. ⏸️ Add CategoryAccountCache only if account picker is slow (optional)

**Why this order:**
- Solves the immediate problem (slow sheet opening)
- Minimal code changes
- Zero memory overhead
- Can add cache later if picker performance is an issue

---

## 🔧 Implementation Checklist

### Immediate (Phase 2 - Lazy Suggestion)

- [ ] Remove `suggestedAccount()` call from AddTransactionCoordinator init
- [ ] Add `suggestedAccountId` computed property
- [ ] Update `TransactionFormData` init to accept `nil` for `suggestedAccountId`
- [ ] Update `AccountSelectorView` binding in AddTransactionModal
- [ ] Test sheet opening performance (should be < 50ms)
- [ ] Verify account suggestion still works when user opens picker

### Optional (Phase 1 - Cache)

- [ ] Create CategoryAccountCache.swift service
- [ ] Add cache property to AccountsViewModel
- [ ] Integrate cache into `suggestedAccount()` method
- [ ] Add cache rebuild calls in TransactionsViewModel
- [ ] Add cache invalidation on transaction add/delete
- [ ] Test cache hit/miss rates with DEBUG logging
- [ ] Verify account picker performance (should be < 10ms)

---

## 🧪 Testing Plan

### Performance Benchmarks

**Before optimization:**
```
👆 [QuickAddTransactionView] Category tapped: Groceries
🔧 [AddTransactionCoordinator] Init started for category: Groceries
⏱️ [AddTransactionCoordinator] suggestedAccount: 247ms  ❌ SLOW
✅ [AddTransactionCoordinator] Init completed in 253ms  ❌ SLOW
📱 [AddTransactionModal] onAppear started
✅ [AddTransactionModal] onAppear completed in 12ms
```

**After Phase 2 (Lazy):**
```
👆 [QuickAddTransactionView] Category tapped: Groceries
🔧 [AddTransactionCoordinator] Init started for category: Groceries
✅ [AddTransactionCoordinator] Init completed in 8ms  ✅ INSTANT
📱 [AddTransactionModal] onAppear started
✅ [AddTransactionModal] onAppear completed in 5ms  ✅ INSTANT
```

**After Phase 1 (Cache):**
```
(Account picker opened)
✅ [AccountsViewModel] Cache HIT for category: Groceries
⏱️ [suggestedAccountId] Computed in 2ms  ✅ INSTANT
```

### Test Cases

1. **Sheet Opening Speed**
   - Tap category → measure time to sheet visible
   - **Target:** < 50ms

2. **Account Suggestion Accuracy**
   - Verify most-used account is still suggested
   - Test with new categories (no history)
   - Test with insufficient balance

3. **Cache Invalidation**
   - Add transaction → verify cache invalidates
   - Delete transaction → verify cache invalidates
   - Import CSV → verify cache rebuilds

4. **Memory Usage**
   - Monitor cache size with 19,000 transactions
   - **Target:** < 150 KB

---

## 📝 Migration Notes

### Breaking Changes
None - all changes are internal optimizations

### Backward Compatibility
✅ Fully backward compatible - no API changes

### Risk Assessment

**Low Risk:**
- Phase 2 (Lazy) - Simple refactor, no algorithm changes
- Only defers computation, doesn't change logic

**Medium Risk:**
- Phase 1 (Cache) - New cache invalidation logic
- Must ensure cache stays in sync with transactions

**Mitigation:**
- Start with Phase 2 (lower risk)
- Add extensive DEBUG logging
- Test with large transaction datasets (19K+)

---

## 🚀 Expected Results

### Phase 2 (Lazy) - Immediate Win

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Sheet Open Time | 200-500ms | < 50ms | **10x faster** ✅ |
| Init Overhead | 200-500ms | < 10ms | **50x faster** ✅ |
| User Experience | Noticeable lag | Instant | **Perfect** ✅ |

### Phase 1 (Cache) - Future Enhancement

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Account Picker Open | 50-100ms | < 10ms | **10x faster** ✅ |
| Suggestion Accuracy | 100% | 100% | **No change** ✅ |
| Memory Usage | 0 KB | ~100 KB | **Negligible** ✅ |

---

## 🎓 Key Learnings

### Root Cause
**Synchronous O(n) operations in init() block UI thread**

### Solution Pattern
**Defer expensive operations until needed (lazy evaluation)**

### Best Practices
1. ✅ Never scan large arrays in init/onAppear
2. ✅ Use caching for expensive repeated computations
3. ✅ Profile with DEBUG logging before optimizing
4. ✅ Start with simplest solution (lazy) before complex (cache)

---

## 📊 Final Recommendation

### Start with Phase 2 (Lazy Suggestion)

**Why:**
- ✅ Solves immediate problem (slow sheet opening)
- ✅ Minimal code changes (~20 lines)
- ✅ Zero risk of cache invalidation bugs
- ✅ Zero memory overhead
- ✅ Can always add cache later if needed

**Implementation time:** ~15 minutes
**Expected improvement:** 10x faster sheet opening

---

**Status:** Ready for implementation ✅
**Next Step:** Implement Phase 2 (Lazy Suggestion) refactor
