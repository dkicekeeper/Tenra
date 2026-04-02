//
//  CategoryBudgetServiceTests.swift
//  AIFinanceManagerTests
//
//  Unit tests for CategoryBudgetService.budgetProgress, budgetPeriodStart, calculateSpent.
//  TEST-02
//

import Testing
import Foundation
@testable import AIFinanceManager

@Suite("CategoryBudgetService")
struct CategoryBudgetServiceTests {

    // MARK: - Shared service instance (no currency conversion)

    private let service = CategoryBudgetService()

    // MARK: - Helpers

    private func todayString() -> String {
        DateFormatters.dateFormatter.string(from: Date())
    }

    /// Build a test expense category with an optional budget.
    private func makeExpenseCategory(
        name: String = "Food",
        budgetAmount: Double? = 500,
        budgetResetDay: Int = 1,
        budgetPeriod: CustomCategory.BudgetPeriod = .monthly
    ) -> CustomCategory {
        CustomCategory(
            id: UUID().uuidString,
            name: name,
            colorHex: "#FF0000",
            type: .expense,
            budgetAmount: budgetAmount,
            budgetPeriod: budgetPeriod,
            budgetResetDay: budgetResetDay
        )
    }

    /// Build a test income category.
    private func makeIncomeCategory(
        name: String = "Salary",
        budgetAmount: Double? = 100
    ) -> CustomCategory {
        CustomCategory(
            id: UUID().uuidString,
            name: name,
            colorHex: "#00FF00",
            type: .income,
            budgetAmount: budgetAmount
        )
    }

    /// Build a test transaction.
    private func makeTransaction(
        amount: Double,
        category: String = "Food",
        date: String,
        type: TransactionType = .expense
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "Test transaction",
            amount: amount,
            currency: "KZT",
            type: type,
            category: category
        )
    }

    // MARK: - Test A: Income category returns nil

    @Test("Income category with budget returns nil (budgets not supported for income)")
    func testIncomeCategoryReturnsNil() {
        let category = makeIncomeCategory(budgetAmount: 100)
        let result = service.budgetProgress(for: category, transactions: [])
        #expect(result == nil, "Income categories must not return a BudgetProgress")
    }

    // MARK: - Test B: Expense category without budget returns nil

    @Test("Expense category without budget amount returns nil")
    func testExpenseCategoryNoBudgetReturnsNil() {
        let category = makeExpenseCategory(budgetAmount: nil)
        let result = service.budgetProgress(for: category, transactions: [])
        #expect(result == nil, "Expense category without budgetAmount must return nil")
    }

    // MARK: - Test C: Zero transactions → spent == 0

    @Test("Zero transactions in period gives spent == 0")
    func testZeroTransactionsPeriod() {
        let category = makeExpenseCategory(budgetAmount: 500)
        let result = service.budgetProgress(for: category, transactions: [])
        #expect(result != nil, "Should return BudgetProgress")
        #expect(result?.spent == 0.0, "No transactions → spent must be 0")
    }

    // MARK: - Test D: Spent exactly equals budget amount

    @Test("Spent exactly at limit: spent == budgetAmount == 200")
    func testSpentExactlyAtLimit() {
        let category = makeExpenseCategory(name: "Food", budgetAmount: 200, budgetResetDay: 1)
        let tx = makeTransaction(amount: 200, category: "Food", date: todayString())
        let result = service.budgetProgress(for: category, transactions: [tx])
        #expect(result != nil, "Should return BudgetProgress")
        #expect(result?.spent == 200.0, "spent must equal transaction amount")
        #expect(result?.budgetAmount == 200.0, "budgetAmount must be 200")
    }

    // MARK: - Test E: Spent below limit

    @Test("Spent below limit: budget 500, three transactions totalling 300")
    func testSpentBelowLimit() {
        let category = makeExpenseCategory(name: "Food", budgetAmount: 500, budgetResetDay: 1)
        let transactions = [
            makeTransaction(amount: 100, category: "Food", date: todayString()),
            makeTransaction(amount: 150, category: "Food", date: todayString()),
            makeTransaction(amount: 50, category: "Food", date: todayString())
        ]
        let result = service.budgetProgress(for: category, transactions: transactions)
        #expect(result != nil, "Should return BudgetProgress")
        #expect(result?.spent == 300.0, "Total of 100+150+50 = 300")
    }

    // MARK: - Test F: Period boundary / reset day rollover

    @Test("budgetPeriodStart respects reset day relative to today")
    func testPeriodBoundaryResetDay() {
        let calendar = Calendar.current
        let currentDay = calendar.component(.day, from: Date())
        let resetDay = 15

        let category = makeExpenseCategory(budgetAmount: 1000, budgetResetDay: resetDay)
        let periodStart = service.budgetPeriodStart(for: category)
        let startDay = calendar.component(.day, from: periodStart)
        let startMonth = calendar.component(.month, from: periodStart)
        let thisMonth = calendar.component(.month, from: Date())

        if currentDay >= resetDay {
            // Period started this month on reset day
            #expect(startDay == resetDay, "Period should start on reset day (\(resetDay)) this month, got day \(startDay)")
            #expect(startMonth == thisMonth, "Period should be in this month (\(thisMonth)), got \(startMonth)")
        } else {
            // Reset day hasn't arrived yet this month — period started last month
            #expect(startDay == resetDay, "Period should start on reset day (\(resetDay)) of previous month, got day \(startDay)")
            // Previous month: startMonth must differ from thisMonth (or year wrapped)
            let previousMonth = thisMonth == 1 ? 12 : thisMonth - 1
            #expect(startMonth == previousMonth, "Period should be in previous month (\(previousMonth)), got \(startMonth)")
        }
    }

    // MARK: - Test G: Transactions outside period are excluded

    @Test("Transaction from 2020 is excluded from current period spending")
    func testTransactionsOutsidePeriodExcluded() {
        let category = makeExpenseCategory(name: "Food", budgetAmount: 500, budgetResetDay: 1)
        // Far-past transaction — always before any current period start
        let oldTx = makeTransaction(amount: 999, category: "Food", date: "2020-01-01")
        let result = service.budgetProgress(for: category, transactions: [oldTx])
        #expect(result != nil, "Should return BudgetProgress")
        #expect(result?.spent == 0.0, "Old transaction must not be counted; expected 0, got \(result?.spent ?? -1)")
    }

    // MARK: - Test H: Wrong category name excluded

    @Test("Only transactions matching category name are counted")
    func testWrongCategoryNameExcluded() {
        let category = makeExpenseCategory(name: "Food", budgetAmount: 500, budgetResetDay: 1)
        let matchingTx = makeTransaction(amount: 200, category: "Food", date: todayString())
        let otherTx = makeTransaction(amount: 999, category: "Entertainment", date: todayString())
        let result = service.budgetProgress(for: category, transactions: [matchingTx, otherTx])
        #expect(result != nil, "Should return BudgetProgress")
        #expect(result?.spent == 200.0, "Only 'Food' transaction (200) must be counted, got \(result?.spent ?? -1)")
    }
}
