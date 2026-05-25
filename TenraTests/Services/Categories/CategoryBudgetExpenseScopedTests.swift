//
//  CategoryBudgetExpenseScopedTests.swift
//  TenraTests
//
//  H-6 / C-6 residual: budget "spent" must be EXPENSE-only, txDate<=today,
//  base currency — and the store budget path (CategoryBudgetService over the
//  pre-aggregated buckets) must agree with the Insights legacy path
//  (calculateSpentLegacy over a [Transaction] snapshot).
//
//  The bug: the store category bucket (categoryAggregatesByKey.totalAmount)
//  sums ALL aggregatable types (expense + income + deposit + loan), so an
//  income/loan/deposit tx tagged to a *budgeted expense category* inflated the
//  store-path "spent" while Insights (expense-only) did not. They must match.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryBudgetExpenseScopedTests {

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

    private static func tx(
        id: String,
        amount: Double,
        type: TransactionType,
        date: String,
        category: String = "Food"
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: "",
            amount: amount, currency: "KZT", convertedAmount: nil,
            type: type, category: category, subcategory: nil,
            accountId: "a1", targetAccountId: nil
        )
    }

    private static func thisMonthDateString(day: Int = 5) -> String {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.day = day
        // Clamp to a day that has already happened this month (<= today).
        let today = cal.component(.day, from: now)
        comps.day = min(day, today)
        let date = cal.date(from: comps) ?? now
        return DateFormatters.dateFormatter.string(from: date)
    }

    private static func budgetedFoodCategory() -> CustomCategory {
        CustomCategory(
            id: "id-food", name: "Food",
            iconSource: .sfSymbol("fork.knife"), colorHex: "#FF0000",
            type: .expense, budgetAmount: 50_000,
            budgetPeriod: .monthly, budgetResetDay: 1
        )
    }

    /// CORE: an income tx tagged to a budgeted EXPENSE category must NOT inflate
    /// the store-path "spent"; it must equal the expense-only Insights total.
    @Test("income tagged to expense budget does not inflate store spent; matches Insights")
    func incomeTaggedToExpenseBudgetMatchesInsights() {
        let store = Self.makeStore()
        let date = Self.thisMonthDateString()
        let txs = [
            Self.tx(id: "e1", amount: 8_000,  type: .expense, date: date),
            Self.tx(id: "e2", amount: 3_000,  type: .expense, date: date),
            // Income mistakenly tagged to the "Food" expense category.
            Self.tx(id: "i1", amount: 99_000, type: .income,  date: date),
        ]
        for t in txs { store.categoryIndexAdd(t) }

        let cat = Self.budgetedFoodCategory()
        let storeSpent = CategoryBudgetService(store: store).calculateSpent(for: cat, store: store)

        // Insights legacy path: expense-only over the [Transaction] snapshot.
        let insightsSpent = CategoryBudgetService.calculateSpentLegacy(
            for: cat, transactions: txs, baseCurrency: "KZT"
        )

        #expect(insightsSpent == 11_000, "Insights counts only expenses (8000+3000)")
        #expect(storeSpent == 11_000, "Store path must be expense-only too, not 110000")
        #expect(storeSpent == insightsSpent, "Store and Insights budget 'spent' must agree")
    }

    /// Loan/deposit tx tagged to an expense category likewise must not count.
    @Test("loan payment tagged to expense budget does not count toward spent")
    func loanTaggedToExpenseBudgetExcluded() {
        let store = Self.makeStore()
        let date = Self.thisMonthDateString()
        let txs = [
            Self.tx(id: "e1", amount: 5_000, type: .expense, date: date),
            Self.tx(id: "l1", amount: 40_000, type: .loanPayment, date: date),
        ]
        for t in txs { store.categoryIndexAdd(t) }

        let cat = Self.budgetedFoodCategory()
        let storeSpent = CategoryBudgetService(store: store).calculateSpent(for: cat, store: store)
        #expect(storeSpent == 5_000, "Only the expense counts toward budget spent")
    }

    /// Pure-expense category: store path unchanged.
    @Test("pure-expense category spent is unchanged")
    func pureExpenseUnchanged() {
        let store = Self.makeStore()
        let date = Self.thisMonthDateString()
        let txs = [
            Self.tx(id: "e1", amount: 1_500, type: .expense, date: date),
            Self.tx(id: "e2", amount: 2_500, type: .expense, date: date),
        ]
        for t in txs { store.categoryIndexAdd(t) }

        let cat = Self.budgetedFoodCategory()
        let storeSpent = CategoryBudgetService(store: store).calculateSpent(for: cat, store: store)
        #expect(storeSpent == 4_000)
    }
}
