//
//  TransactionCacheManager.swift
//  AIFinanceManager
//
//  PURPOSE (Phase 36+): READ-ONLY display cache. Do NOT use for write operations.
//
//  ROLE CLARITY (updated Phase 36):
//  ─────────────────────────────────────────────────────────────────────────────
//  ✅ TransactionCacheManager — in-memory read cache for display layer only:
//      • Date string → Date parsing (O(1) repeat parses)
//      • Transaction ID → Subcategory IDs index (built once per load)
//      • Summary cache (total income/expenses for current filter)
//      • Per-filter category expense cache (keyed by TimeFilter)
//      • Category list caches (unique, expense, income names)
//
//  ❌ NOT for:
//      • Account balances — use BalanceCoordinator instead
//      • Transaction persistence — use TransactionStore.apply(event:)
//      • Aggregate data — use CategoryAggregateService / MonthlyAggregateService (CoreData)
//      • Budget spending — use BudgetSpendingCacheService (CoreData)
//  ─────────────────────────────────────────────────────────────────────────────
//
//  ACTIVE CALLERS:
//      • TransactionGroupingService — getParsedDate() for date section grouping
//      • TransactionQueryService — category expense caching + summary cache
//      • TransactionsViewModel — invalidateAll() on data change events
//

import Foundation

// MARK: - Read-Only Display Cache (Phase 36+)

/// In-memory cache for read-only UI display operations.
/// Write/mutation caching is handled by TransactionStore + CoreData aggregate services.
/// This class is @MainActor-compatible (not marked @MainActor; callers ensure main-thread use).
nonisolated class TransactionCacheManager {

    // MARK: - Date Parsing Cache (for display performance)

    private var parsedDateCache: [String: Date] = [:]
    private let dateFormatter = DateFormatter()

    init() {
        dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    /// Get cached parsed date (O(1) lookup)
    func getParsedDate(for dateString: String) -> Date? {
        if let cached = parsedDateCache[dateString] {
            return cached
        }
        if let parsed = dateFormatter.date(from: dateString) {
            parsedDateCache[dateString] = parsed
            return parsed
        }
        return nil
    }

    // MARK: - Subcategory Index Cache (for display)

    private var subcategoryIndex: [String: Set<String>] = [:]

    func getSubcategoryIds(for transactionId: String) -> Set<String> {
        return subcategoryIndex[transactionId] ?? []
    }

    func buildSubcategoryIndex(links: [TransactionSubcategoryLink]) {
        subcategoryIndex.removeAll()
        for link in links {
            if subcategoryIndex[link.transactionId] == nil {
                subcategoryIndex[link.transactionId] = []
            }
            subcategoryIndex[link.transactionId]?.insert(link.subcategoryId)
        }
    }

    // MARK: - Category Expenses Cache (for summary display)

    var summaryCacheInvalidated = false
    var cachedSummary: Summary?

    /// Per-filter cache: key is TimeFilter.stableCacheKey string, value is expenses dict.
    /// Fixes the bug where all time filters shared a single cached result.
    private var cachedCategoryExpensesByFilter: [String: [String: CategoryExpense]] = [:]

    // Category lists cache
    var categoryListsCacheInvalidated = false
    var cachedUniqueCategories: [String]?
    var cachedExpenseCategories: [String]?
    var cachedIncomeCategories: [String]?

    func invalidateCategoryExpenses() {
        summaryCacheInvalidated = true
        cachedSummary = nil
        cachedCategoryExpensesByFilter.removeAll()
    }

    func getCachedCategoryExpenses(for key: Any) -> [String: CategoryExpense]? {
        guard !summaryCacheInvalidated else { return nil }
        let cacheKey = stableCacheKey(from: key)
        return cachedCategoryExpensesByFilter[cacheKey]
    }

    func setCachedCategoryExpenses(_ expenses: [String: CategoryExpense], for key: Any) {
        let cacheKey = stableCacheKey(from: key)
        cachedCategoryExpensesByFilter[cacheKey] = expenses
        summaryCacheInvalidated = false
    }

    /// Derive a stable string key from the provided key (TimeFilter or any Hashable).
    private func stableCacheKey(from key: Any) -> String {
        if let timeFilter = key as? TimeFilter {
            return timeFilter.stableCacheKey
        }
        return String(describing: key)
    }

    func invalidateAll() {
        parsedDateCache.removeAll()
        subcategoryIndex.removeAll()
        cachedSummary = nil
        cachedCategoryExpensesByFilter.removeAll()
        cachedUniqueCategories = nil
        cachedExpenseCategories = nil
        cachedIncomeCategories = nil
        summaryCacheInvalidated = true
        categoryListsCacheInvalidated = true
    }

    // MARK: - Index Rebuild

    func rebuildIndexes(transactions: [Transaction]) {
        // Date cache is built on-demand via getParsedDate
        // Just clear it to force rebuild
        parsedDateCache.removeAll()
    }
}
