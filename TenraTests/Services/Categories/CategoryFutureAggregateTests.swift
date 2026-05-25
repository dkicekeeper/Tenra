//
//  CategoryFutureAggregateTests.swift
//  TenraTests
//
//  C-6 / H-3 / H-4: budget "spent" and category totals are realized actuals — they must
//  exclude future-dated transactions (incl. generated recurring), matching the balance and
//  account-aggregate policy. Also pins the legacy/Insights budget period start so it agrees
//  with the store path when budgetStartDate is nil.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryFutureAggregateTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        return TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
    }

    private static func expenseTx(id: String, amount: Double, date: String, category: String = "Food") -> Transaction {
        Transaction(
            id: id, date: date, description: "",
            amount: amount, currency: "KZT", convertedAmount: nil,
            type: .expense, category: category, subcategory: nil,
            accountId: "a1", targetAccountId: nil
        )
    }

    private static func futureDateString(daysAhead: Int = 40) -> String {
        DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: daysAhead, to: Date())!
        )
    }

    private static func pastDateString(daysAgo: Int = 5) -> String {
        DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )
    }

    @Test("future-dated transaction is excluded from category aggregate buckets")
    func futureTxExcludedFromCategoryBuckets() async {
        let store = Self.makeStore()
        store.categoryIndexAdd(Self.expenseTx(id: "f1", amount: 500, date: Self.futureDateString()))
        store.categoryIndexAdd(Self.expenseTx(id: "p1", amount: 200, date: Self.pastDateString()))

        let allTimeKey = CategoryAggregate.makeId(category: "Food", year: 0, month: 0, day: 0)
        #expect(store.categoryAggregatesByKey[allTimeKey]?.totalAmount == 200)
    }

    @Test("legacy budget period start is a real period start even when budgetStartDate is nil")
    func legacyPeriodStartIgnoresNilBudgetStartDate() {
        var cat = CustomCategory(
            id: "id-food", name: "Food",
            iconSource: .sfSymbol("fork.knife"), colorHex: "#FF0000",
            type: .expense, budgetAmount: 50_000,
            budgetPeriod: .monthly, budgetResetDay: 1
        )
        cat.budgetStartDate = nil  // legacy data: budget set but no start date persisted
        let start = CategoryBudgetService.legacyBudgetPeriodStart(for: cat)
        // With resetDay=1 the period started on the 1st of this month — comfortably
        // more than a day ago. The old nil short-circuit returned ~now (≈0s ago).
        #expect(Date().timeIntervalSince(start) > 86_400)
    }
}
