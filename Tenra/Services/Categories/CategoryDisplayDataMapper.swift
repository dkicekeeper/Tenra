//
//  CategoryDisplayDataMapper.swift
//  Tenra
//
//  Maps categories to display data with totals and budget information.
//  Extracted from QuickAddTransactionView to follow Single Responsibility Principle.
//

import Foundation
import SwiftUI

@MainActor
final class CategoryDisplayDataMapper: CategoryDisplayDataMapperProtocol {

    // MARK: - Memoization Cache

    /// Cache key for memoization. Uses content fingerprints (counts + a content
    /// hash for the expenses map + an order fingerprint) — strictly cheaper than
    /// the previous design which built a sorted-join string of every category's
    /// fields on EVERY call.
    ///
    /// We can't rely on `categoriesMutationVersion` here because the mapper has
    /// no `TransactionStore` reference, so the key must fingerprint everything the
    /// output depends on. A reorder changes only each category's `.order` value
    /// (count / names / totals stay identical), so `orderHash` is what keeps the
    /// sort fresh — without it the stale order survives until app restart.
    private struct CacheKey: Hashable {
        let categoriesCount: Int
        let expensesHash: Int
        let orderHash: Int
        let type: TransactionType
        let baseCurrency: String
        let filterCacheKey: String

        init(customCategories: [CustomCategory], categoryExpenses: [String: CategoryExpense], type: TransactionType, baseCurrency: String, currentFilter: TimeFilter) {
            self.categoriesCount = customCategories.count

            // Single XOR-combiner over (key, total)-pair hashes — O(N_expenses)
            // bytes of work, no sort, no string allocs.
            var expHash = 0
            for (k, v) in categoryExpenses {
                expHash ^= k.hashValue
                expHash ^= Int(bitPattern: UInt(bitPattern: v.total.bitPattern.hashValue))
            }
            self.expensesHash = expHash

            // Sequence-sensitive fingerprint of (id, order) so a reorder — which swaps
            // `.order` values without changing count/names/totals — produces a new key.
            // Hasher.combine IS order-sensitive (unlike the XOR above), which is exactly
            // what we need to distinguish a same-set swap.
            var orderHasher = Hasher()
            for cat in customCategories {
                orderHasher.combine(cat.id)
                orderHasher.combine(cat.order)
            }
            self.orderHash = orderHasher.finalize()

            self.type = type
            self.baseCurrency = baseCurrency
            self.filterCacheKey = currentFilter.stableCacheKey
        }
    }

    /// Cached result to avoid redundant mapping.
    private var cache: (key: CacheKey, result: [CategoryDisplayData])?

    // MARK: - Public Methods

    func mapCategories(
        customCategories: [CustomCategory],
        categoryExpenses: [String: CategoryExpense],
        type: TransactionType,
        baseCurrency: String,
        currentFilter: TimeFilter
    ) -> [CategoryDisplayData] {
        // ✅ OPTIMIZATION: Check cache first
        let cacheKey = CacheKey(
            customCategories: customCategories,
            categoryExpenses: categoryExpenses,
            type: type,
            baseCurrency: baseCurrency,
            currentFilter: currentFilter
        )

        if let cached = cache, cached.key == cacheKey {
            return cached.result
        }

        // Filter categories by type and pre-index them for O(1) lookup. The previous
        // implementation did a `customCategories.first { $0.name.lowercased() == ... }`
        // per category — O(N_cat²) overall. We pay O(N_cat) once and look up by
        // case-folded name afterwards.
        let filteredCategories = customCategories.filter { $0.type == type }
        var categoryByLowerName: [String: CustomCategory] = [:]
        categoryByLowerName.reserveCapacity(filteredCategories.count)
        for cat in filteredCategories {
            categoryByLowerName[cat.name.lowercased()] = cat
        }

        // Collect all unique categories from custom categories and expenses.
        var allCategories = Set<String>()
        for category in filteredCategories {
            allCategories.insert(category.name)
        }
        for categoryName in categoryExpenses.keys
        where categoryByLowerName[categoryName.lowercased()] != nil {
            allCategories.insert(categoryName)
        }

        // Map to display data — each call is O(1) name lookup.
        let displayData = allCategories.compactMap { categoryName -> CategoryDisplayData? in
            mapCategory(
                name: categoryName,
                categoryByLowerName: categoryByLowerName,
                filteredCategories: filteredCategories,
                categoryExpenses: categoryExpenses,
                type: type,
                baseCurrency: baseCurrency,
                currentFilter: currentFilter
            )
        }

        // Create a lookup for category order. `uniquingKeysWith` (not `uniqueKeysWithValues`)
        // because two categories of the same `type` can briefly share a name during
        // import / re-seeded onboarding — the strict initializer crashes the whole
        // app instead of just degrading the sort.
        let orderLookup = Dictionary(
            filteredCategories.compactMap { category -> (String, Int)? in
                guard let order = category.order else { return nil }
                return (category.name, order)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Sort by custom order if available, otherwise by name
        let result = displayData.sorted { category1, category2 in
            let order1 = orderLookup[category1.name]
            let order2 = orderLookup[category2.name]

            // If both have custom order, sort by order
            if let o1 = order1, let o2 = order2 {
                return o1 < o2
            }
            // If only one has custom order, it goes first
            if order1 != nil {
                return true
            }
            if order2 != nil {
                return false
            }
            // If neither has custom order, sort by name
            return category1.name < category2.name
        }

        // ✅ OPTIMIZATION: Cache the result
        cache = (cacheKey, result)

        return result
    }

    // MARK: - Private Methods

    private func mapCategory(
        name: String,
        categoryByLowerName: [String: CustomCategory],
        filteredCategories: [CustomCategory],
        categoryExpenses: [String: CategoryExpense],
        type: TransactionType,
        baseCurrency: String,
        currentFilter: TimeFilter
    ) -> CategoryDisplayData? {
        // O(1) name lookup via the dictionary prepared by `mapCategories`.
        let customCategory = categoryByLowerName[name.lowercased()]

        // Get total from expenses
        let total = categoryExpenses[name]?.total ?? 0

        // Get budget progress with filter-aware budget scaling
        let budgetProgress = customCategory.flatMap { category -> BudgetProgress? in
            guard let budgetAmount = category.budgetAmount, budgetAmount > 0,
                  let scaled = scaledBudgetAmount(budgetAmount, period: category.budgetPeriod, filter: currentFilter)
            else { return nil }
            return BudgetProgress(budgetAmount: scaled, spent: total)
        }

        // Cached style data — O(1) on hit; miss only after explicit invalidation.
        let styleData = CategoryStyleHelper.cached(
            category: name,
            type: type,
            customCategories: filteredCategories
        )

        // Deterministic id — prevents spurious ForEach animations on cache invalidation
        return CategoryDisplayData(
            id: customCategory?.id ?? "\(name)_\(type.rawValue)",
            name: name,
            type: type,
            iconName: styleData.iconName,
            iconColor: styleData.iconColor,
            total: total,
            budgetAmount: budgetProgress?.budgetAmount,
            budgetProgress: budgetProgress
        )
    }

    // MARK: - Budget Scaling

    /// Returns nil for filters where budget comparison is meaningless.
    /// Returns the original amount for exact period matches (no rounding errors).
    /// Otherwise scales proportionally via daily rate.
    private func scaledBudgetAmount(
        _ amount: Double,
        period: CustomCategory.BudgetPeriod,
        filter: TimeFilter
    ) -> Double? {
        // Never show budget for open-ended or rolling filters
        guard filter.preset != .allTime, filter.preset != .last30Days else { return nil }

        // Exact match: return original amount (avoids floating-point rounding)
        switch (filter.preset, period) {
        case (.thisMonth, .monthly), (.lastMonth, .monthly): return amount
        case (.thisWeek, .weekly):                           return amount
        case (.thisYear, .yearly), (.lastYear, .yearly):     return amount
        default: break
        }

        // Scale proportionally: convert budget to daily rate × filter days
        let calendar = Calendar.current
        let filterDays = Double(
            calendar.dateComponents([.day], from: filter.startDate, to: filter.endDate).day ?? 30
        )
        let periodDays: Double
        switch period {
        case .monthly: periodDays = 365.25 / 12   // 30.4375
        case .weekly:  periodDays = 7
        case .yearly:  periodDays = 365.25
        @unknown default: periodDays = 365.25 / 12
        }

        return amount / periodDays * filterDays
    }
}
