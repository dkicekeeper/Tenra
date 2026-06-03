//
//  CategoryDisplayDataMapperTests.swift
//  TenraTests
//
//  Regression coverage for the mapper's memoization cache: a reorder changes
//  only each category's `.order` value (count / names / totals stay the same),
//  so the cache key MUST fingerprint order or stale ordering survives until the
//  app restarts (fresh mapper = empty cache).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryDisplayDataMapperTests {

    private func makeCategory(_ name: String, order: Int) -> CustomCategory {
        CustomCategory(name: name, colorHex: "#FF0000", type: .expense, order: order)
    }

    @Test("Reordering categories updates mapped output order within a session")
    func reorderInvalidatesCache() {
        let mapper = CategoryDisplayDataMapper()
        let filter = TimeFilter(preset: .allTime)
        let expenses: [String: CategoryExpense] = [:]

        let first = mapper.mapCategories(
            customCategories: [makeCategory("Food", order: 0), makeCategory("Travel", order: 1)],
            categoryExpenses: expenses,
            type: .expense,
            baseCurrency: "USD",
            currentFilter: filter
        )
        #expect(first.map(\.name) == ["Food", "Travel"])

        // Same categories, same count / names / totals — only the order values swap.
        let second = mapper.mapCategories(
            customCategories: [makeCategory("Food", order: 1), makeCategory("Travel", order: 0)],
            categoryExpenses: expenses,
            type: .expense,
            baseCurrency: "USD",
            currentFilter: filter
        )
        #expect(second.map(\.name) == ["Travel", "Food"])
    }
}
