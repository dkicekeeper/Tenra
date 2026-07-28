//
//  TransactionCacheManager.swift
//  Tenra
//
//  READ-ONLY display cache. Do NOT use for write operations.
//
//  ROLE CLARITY:
//  ─────────────────────────────────────────────────────────────────────────────
//  TransactionCacheManager — in-memory read cache for display layer only:
//      • Date string → Date parsing (O(1) repeat parses)
//      • Transaction ID → Subcategory IDs index (built once per load)
//      • Summary cache (total income/expenses for current filter)
//      • Per-filter category expense cache (keyed by TimeFilter)
//      • Category list caches (unique, expense, income names)
//
//  NOT for:
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

// MARK: - Read-Only Display Cache

/// In-memory cache for read-only UI display operations.
/// Write/mutation caching is handled by TransactionStore + CoreData aggregate services.
/// This class is @MainActor-compatible (not marked @MainActor; callers ensure main-thread use).
nonisolated class TransactionCacheManager {

    // MARK: - Date Parsing Cache (for display performance)

    private var parsedDateCache: [String: Date] = [:]
    private let dateFormatter = DateFormatter()

    init() {
        dateFormatter.dateFormat = "yyyy-MM-dd"
        // locale/calendar are NOT optional here. A DateFormatter without an explicit
        // locale inherits the device region's calendar, so on a device set to Thailand
        // (Buddhist) or Saudi Arabia (Umm al-Qura) `date(from: "2026-07-28")` yields a
        // different date — or nil. TransactionGroupingService.parseDate() routes through
        // this cache, so history date grouping silently broke for those users.
        // Matches the canonical DateFormatters.dateFormatter contract.
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = .current
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

    /// Gate for the per-filter category-expenses cache below. (The summary card
    /// computes fresh every time — `TransactionQueryService.calculateSummary` no
    /// longer caches, since a single unkeyed slot returned one filter's totals for
    /// every filter; see cache audit #14.)
    var categoryExpensesCacheInvalidated = false

    /// Per-filter cache: key is TimeFilter.stableCacheKey string, value is expenses dict.
    /// Fixes the bug where all time filters shared a single cached result.
    private var cachedCategoryExpensesByFilter: [String: [String: CategoryExpense]] = [:]

    // Category lists cache. nil = needs recompute (the previous shared
    // `categoryListsCacheInvalidated` flag was never reset to false, so once set it
    // forced an O(N) rescan on every access; and the normal tx-mutation path never
    // set it at all, leaving the lists stale — cache audit #6). nil-means-invalid is
    // self-resetting: the accessor recomputes and repopulates per list.
    var cachedUniqueCategories: [String]?
    var cachedExpenseCategories: [String]?
    var cachedIncomeCategories: [String]?

    private func invalidateCategoryLists() {
        cachedUniqueCategories = nil
        cachedExpenseCategories = nil
        cachedIncomeCategories = nil
    }

    func invalidateCategoryExpenses() {
        categoryExpensesCacheInvalidated = true
        cachedCategoryExpensesByFilter.removeAll()
        // Adding/removing a transaction can change which categories have activity.
        invalidateCategoryLists()
    }

    func getCachedCategoryExpenses(for key: Any) -> [String: CategoryExpense]? {
        guard !categoryExpensesCacheInvalidated else { return nil }
        let cacheKey = stableCacheKey(from: key)
        return cachedCategoryExpensesByFilter[cacheKey]
    }

    func setCachedCategoryExpenses(_ expenses: [String: CategoryExpense], for key: Any) {
        let cacheKey = stableCacheKey(from: key)
        cachedCategoryExpensesByFilter[cacheKey] = expenses
        categoryExpensesCacheInvalidated = false
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
        cachedCategoryExpensesByFilter.removeAll()
        invalidateCategoryLists()
        categoryExpensesCacheInvalidated = true
    }

    // MARK: - Index Rebuild

    func rebuildIndexes(transactions: [Transaction]) {
        // Date cache is built on-demand via getParsedDate
        // Just clear it to force rebuild
        parsedDateCache.removeAll()
    }
}
