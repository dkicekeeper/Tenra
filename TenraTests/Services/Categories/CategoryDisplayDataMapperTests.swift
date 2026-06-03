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

    // NOTE: colorHex is also folded into appearanceHash (same loop as budgetAmount).
    // It isn't unit-tested separately here because the resulting iconColor flows
    // through the process-global CategoryStyleCache singleton, which races across
    // swift-testing's parallel suites; the budget case below exercises the identical
    // appearanceHash key-invalidation mechanism deterministically.
    @Test("Setting a category's budget updates the mapped output within a session")
    func budgetEditInvalidatesCache() {
        let mapper = CategoryDisplayDataMapper()
        let filter = TimeFilter(preset: .thisMonth)
        let expenses: [String: CategoryExpense] = ["Food": CategoryExpense(total: 50, subcategories: [:])]
        let id = "cat-food"

        let noBudget = mapper.mapCategories(
            customCategories: [CustomCategory(id: id, name: "Food", colorHex: "#FF0000", type: .expense, order: 0)],
            categoryExpenses: expenses,
            type: .expense,
            baseCurrency: "USD",
            currentFilter: filter
        )
        #expect(noBudget.first?.budgetProgress == nil)

        // Same id/name/count/order/total — only a budget was added.
        let withBudget = mapper.mapCategories(
            customCategories: [CustomCategory(id: id, name: "Food", colorHex: "#FF0000", type: .expense, budgetAmount: 100, order: 0)],
            categoryExpenses: expenses,
            type: .expense,
            baseCurrency: "USD",
            currentFilter: filter
        )
        #expect(withBudget.first?.budgetProgress != nil)
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
