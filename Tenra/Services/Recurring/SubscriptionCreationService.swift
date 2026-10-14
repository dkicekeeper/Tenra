//
//  SubscriptionCreationService.swift
//  Tenra
//
//  Writing a subscription the way its edit screen always has (docs/domains/recurring.md), so
//  the screen and the assistant's `draft_recurring` share one path: the rate check for a series
//  in another currency than its account, the series itself, and the subcategory named after the
//  subscription, linked to its category and to the transactions the generator made. A generic
//  recurring payment gets the rate check and the series, without the subcategory.
//

import Foundation

enum SubscriptionCreationService {
    enum Failure: Error, Equatable {
        /// No rate from the series' currency to its account's: its occurrences would move the
        /// balance by the raw foreign amount.
        case missingRate
    }

    /// Creates the series and, for a subscription, links its subcategory (red flag 5: the
    /// generated transactions are in the store once `createSeries` returns).
    static func create(_ series: RecurringSeries, store: TransactionStore, categoriesViewModel: CategoriesViewModel) async throws {
        guard await hasAccountRate(for: series, store: store) else { throw Failure.missingRate }
        guard series.kind == .subscription else {
            try await store.createSeries(series)
            return
        }
        let subcategory = resolveOrCreateSubcategory(name: series.description, categoryName: series.category, store: store, categoriesViewModel: categoriesViewModel)
        try await store.createSeries(series)
        linkSubcategory(subcategory, toTransactions: store.transactionsBySeriesId[series.id] ?? [], categoriesViewModel: categoriesViewModel)
    }

    /// Whether the series' amount can be converted into its account's currency, loading the
    /// rate on a cache miss.
    static func hasAccountRate(for series: RecurringSeries, store: TransactionStore) async -> Bool {
        guard let accountCurrency = series.accountId.flatMap({ store.accountById[$0]?.currency }),
              accountCurrency != series.currency else { return true }
        if TransactionConversion.cachedRate(1, series.currency, accountCurrency) != nil { return true }
        await TransactionConversion.loadRates(Set([series.currency, accountCurrency]))
        return TransactionConversion.cachedRate(1, series.currency, accountCurrency) != nil
    }

    /// The subcategory by case-insensitive name, created when missing, linked to the category.
    static func resolveOrCreateSubcategory(name: String, categoryName: String, store: TransactionStore, categoriesViewModel: CategoriesViewModel) -> Subcategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subcategory = categoriesViewModel.subcategories.first {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        } ?? categoriesViewModel.addSubcategory(name: trimmed)
        let categoryId = store.categoryIdByName[categoryName.lowercased()]
            ?? store.categories.first { $0.name == categoryName }?.id
        if let categoryId, !categoriesViewModel.categorySubcategoryLinks.contains(where: {
            $0.subcategoryId == subcategory.id && $0.categoryId == categoryId
        }) {
            categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategory.id, categoryId: categoryId)
        }
        return subcategory
    }

    /// Links the subcategory to the transactions that lack it, in one batch: one link-table write
    /// and one usage-stats rebuild, not one per transaction.
    static func linkSubcategory(_ subcategory: Subcategory, toTransactions transactions: [Transaction], categoriesViewModel: CategoriesViewModel) {
        var links: [String: [String]] = [:]
        for transaction in transactions where links[transaction.id] == nil {
            let existing = categoriesViewModel.getSubcategoriesForTransaction(transaction.id).map(\.id)
            if existing.contains(subcategory.id) { continue }
            links[transaction.id] = existing + [subcategory.id]
        }
        guard !links.isEmpty else { return }
        categoriesViewModel.batchLinkSubcategoriesToTransaction(links)
    }
}
