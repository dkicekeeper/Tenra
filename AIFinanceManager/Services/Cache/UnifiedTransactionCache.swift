//
//  UnifiedTransactionCache.swift
//  AIFinanceManager
//
//  Created on 2026-02-05
//  Refactoring Phase 0: Unified Cache with LRU Eviction
//

import Foundation

/// Unified cache for all transaction-derived data
/// Replaces:
/// - TransactionCacheManager.cachedSummary
/// - TransactionCacheManager.cachedCachedCategoryExpenses
/// - DateSectionExpensesCache
/// - Parts of CategoryAggregateCacheOptimized
///
/// Uses LRU eviction to prevent memory leaks
@MainActor
final class UnifiedTransactionCache {
    // MARK: - Properties

    private let lruCache: LRUCache<String, AnyHashable>
    private let capacity: Int

    #if DEBUG
    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0
    #endif

    // MARK: - Initialization

    init(capacity: Int = 1000) {
        self.capacity = capacity
        self.lruCache = LRUCache(capacity: capacity)
    }

    // MARK: - Cache Operations

    /// Get value from cache
    func get<T: Hashable>(_ key: String) -> T? {
        #if DEBUG
        defer {
            if lruCache.get(key) != nil {
                hitCount += 1
            } else {
                missCount += 1
            }
        }
        #endif

        guard let value = lruCache.get(key) else {
            return nil
        }

        return value as? T
    }

    /// Set value in cache
    func set<T: Hashable>(_ key: String, _ value: T) {
        lruCache.set(key, value: value)
    }

    /// Remove specific key from cache
    func remove(_ key: String) {
        lruCache.remove(key)
    }

    /// Invalidates all cache entries.
    /// Prefix-scoped invalidation was evaluated but not implemented — the LRUCache holds at most
    /// 1000 entries (< 50 KB), and full invalidation on a targeted event is acceptably cheap.
    /// All callers pass semantic prefixes (e.g. "balance_", "daily_expenses_"); if prefix-scoped
    /// eviction becomes necessary, add a `keys: Set<String>` property to LRUCache.
    func invalidate(prefix: String) {
        lruCache.removeAll()
    }

    /// Remove all cached data
    func invalidateAll() {
        lruCache.removeAll()

    }

    // MARK: - Cache Statistics

}

// MARK: - Cache Keys

extension UnifiedTransactionCache {
    /// Standard cache key constants
    enum Key {
        // Summary
        static let summary = "summary"
        static let summaryFiltered = "summary_filtered"

        // Category expenses
        static let categoryExpenses = "category_expenses"
        static func categoryExpenses(filter: String) -> String {
            "category_expenses_\(filter)"
        }

        // Daily expenses
        static func dailyExpenses(date: String) -> String {
            "daily_expenses_\(date)"
        }

        // Monthly aggregates
        static func monthlyAggregate(category: String, year: Int, month: Int) -> String {
            "monthly_\(category)_\(year)_\(month)"
        }

        // Yearly aggregates
        static func yearlyAggregate(category: String, year: Int) -> String {
            "yearly_\(category)_\(year)"
        }

        // Currency conversions
        static func currencyConversion(from: String, to: String, amount: Double) -> String {
            "currency_\(from)_\(to)_\(amount)"
        }

        // Account balances
        static func accountBalance(accountId: String) -> String {
            "balance_\(accountId)"
        }
    }
}

// MARK: - Convenience Methods

extension UnifiedTransactionCache {
    /// Get summary from cache
    var summary: Summary? {
        get { get(Key.summary) }
    }

    /// Set summary in cache
    func setSummary(_ summary: Summary) {
        set(Key.summary, summary)
    }

    /// Get category expenses from cache
    var categoryExpenses: [CachedCategoryExpense]? {
        get { get(Key.categoryExpenses) }
    }

    /// Set category expenses in cache
    func setCachedCategoryExpenses(_ expenses: [CachedCategoryExpense]) {
        set(Key.categoryExpenses, expenses)
    }

    /// Get daily expenses from cache
    func dailyExpenses(for date: String) -> Double? {
        get(Key.dailyExpenses(date: date))
    }

    /// Set daily expenses in cache
    func setDailyExpenses(_ amount: Double, for date: String) {
        set(Key.dailyExpenses(date: date), amount)
    }

    /// Get account balance from cache
    func accountBalance(for accountId: String) -> Double? {
        get(Key.accountBalance(accountId: accountId))
    }

    /// Set account balance in cache
    func setAccountBalance(_ balance: Double, for accountId: String) {
        set(Key.accountBalance(accountId: accountId), balance)
    }

    /// Invalidate all time-filtered data
    func invalidateTimeFiltered() {
        invalidate(prefix: "daily_expenses_")
        invalidate(prefix: "monthly_")
        invalidate(prefix: "yearly_")
        remove(Key.summaryFiltered)
    }

    /// Invalidate category-related data
    func invalidateCategoryData() {
        invalidate(prefix: "category_expenses")
        invalidate(prefix: "monthly_")
        invalidate(prefix: "yearly_")
    }

    /// Invalidate balance data
    func invalidateBalances() {
        invalidate(prefix: "balance_")
    }
}

// MARK: - CachedCategoryExpense Helper Model

/// Simplified model for category expenses (for caching)
struct CachedCategoryExpense: Hashable {
    let name: String
    let amount: Double
    let currency: String

    init(name: String, amount: Double, currency: String = "KZT") {
        self.name = name
        self.amount = amount
        self.currency = currency
    }
}
