//
//  CategoryListsCacheTests.swift
//  TenraTests
//
//  Pins cache audit #6: the tx-derived category-name lists (used by the History
//  filter / pickers) must refresh after a transaction mutation. Previously the
//  normal mutation path (invalidateCategoryExpenses) didn't invalidate them, so a
//  new category's name was missing from the filter until restart.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryListsCacheTests {

    private func tx(_ category: String) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: "2026-06-01",
            description: category,
            amount: 10,
            currency: "USD",
            type: .expense,
            category: category
        )
    }

    @Test("expense-category list refreshes after a tx mutation invalidates the cache")
    func expenseListInvalidatesOnMutation() {
        let cache = TransactionCacheManager()
        let query = TransactionQueryService()

        let first = query.getExpenseCategories(transactions: [tx("Food")], cacheManager: cache)
        #expect(first == ["Food"])

        // Simulate the normal add-transaction path (TransactionsViewModel.invalidateCaches).
        cache.invalidateCategoryExpenses()

        let second = query.getExpenseCategories(
            transactions: [tx("Food"), tx("Travel")],
            cacheManager: cache
        )
        #expect(second == ["Food", "Travel"]) // not the stale ["Food"]
    }

    @Test("category list still serves a cache hit when not invalidated")
    func cacheHitWhenValid() {
        let cache = TransactionCacheManager()
        let query = TransactionQueryService()

        _ = query.getExpenseCategories(transactions: [tx("Food")], cacheManager: cache)
        // No invalidation between calls: passing different transactions returns the
        // cached list (proves it is a real cache, not recomputing every call).
        let cached = query.getExpenseCategories(transactions: [tx("Travel")], cacheManager: cache)
        #expect(cached == ["Food"])
    }
}
