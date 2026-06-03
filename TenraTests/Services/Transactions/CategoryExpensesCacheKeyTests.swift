//
//  CategoryExpensesCacheKeyTests.swift
//  TenraTests
//
//  Pins cache audit #9: the per-filter category-expenses cache key now folds in the
//  base currency and the set of valid category names, so a rename/delete (changing
//  validCategoryNames) under the same time filter can't return a stale breakdown.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryExpensesCacheKeyTests {

    private func tx(_ category: String, _ amount: Double) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: "2026-06-01",
            description: category,
            amount: amount,
            currency: "USD",
            type: .expense,
            category: category
        )
    }

    @Test("changing validCategoryNames under the same filter does not return a stale breakdown")
    func validNamesChangeBustsCache() {
        let cache = TransactionCacheManager()
        let query = TransactionQueryService()
        let currency = TransactionCurrencyService()
        let txs = [tx("Food", 100), tx("Travel", 50)]
        let filter = TimeFilter(preset: .allTime)

        let onlyFood = query.getCategoryExpenses(
            timeFilter: filter,
            baseCurrency: "USD",
            validCategoryNames: ["Food"],
            cacheManager: cache,
            transactions: txs,
            currencyService: currency
        )
        #expect(onlyFood["Food"]?.total == 100)
        #expect(onlyFood["Travel"] == nil) // filtered out

        // Same filter, but Travel is now a valid category — must recompute, not reuse
        // the cached Food-only breakdown.
        let both = query.getCategoryExpenses(
            timeFilter: filter,
            baseCurrency: "USD",
            validCategoryNames: ["Food", "Travel"],
            cacheManager: cache,
            transactions: txs,
            currencyService: currency
        )
        #expect(both["Food"]?.total == 100)
        #expect(both["Travel"]?.total == 50) // would be nil if the stale key were reused
    }
}
