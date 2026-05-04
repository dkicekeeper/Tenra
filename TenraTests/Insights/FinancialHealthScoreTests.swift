//
//  FinancialHealthScoreTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

struct FinancialHealthScoreTests {

    @Test("unavailable() initialises every numeric field to zero")
    func testUnavailableDefaults() {
        let score = FinancialHealthScore.unavailable()

        #expect(score.score == 0)
        #expect(score.savingsRateScore == 0)
        #expect(score.budgetAdherenceScore == 0)
        #expect(score.recurringRatioScore == 0)
        #expect(score.emergencyFundScore == 0)
        #expect(score.cashflowScore == 0)

        #expect(score.savingsRatePercent == 0)
        #expect(score.budgetsOnTrack == 0)
        #expect(score.budgetsTotal == 0)
        #expect(score.recurringMonthlyTotal == 0)
        #expect(score.recurringPercentOfIncome == 0)
        #expect(score.monthsCovered == 0)
        #expect(score.avgMonthlyExpenses == 0)
        #expect(score.avgMonthlyNetFlow == 0)
        #expect(score.totalBalance == 0)
        #expect(score.netFlowPercent == 0)
        #expect(score.totalIncomeWindow == 0)
        #expect(score.totalExpensesWindow == 0)
        #expect(score.baseCurrency == "")
        #expect(score.isBudgetComponentActive == false)
    }

    @Test("computeHealthScore populates raw fields from formula inputs")
    func testComputeHealthScorePopulatesRawFields() {
        let score = InsightsService.computeHealthScore(
            totalIncome: 600_000,
            totalExpenses: 510_000,
            latestNetFlow: 90_000,
            baseCurrency: "KZT",
            balanceFor: { _ in 240_000 },
            allTransactions: [],
            categories: [],
            recurringSeries: [],
            accounts: [
                Account(id: "a1", name: "A1", currency: "KZT", balance: 240_000)
            ]
        )

        // 600k income, 510k expense → 15% rate
        #expect(abs(score.savingsRatePercent - 15.0) < 0.01)
        #expect(score.totalIncomeWindow == 600_000)
        #expect(score.totalExpensesWindow == 510_000)
        #expect(score.totalBalance == 240_000)
        #expect(score.baseCurrency == "KZT")
        #expect(score.isBudgetComponentActive == false)  // no budgets passed
        #expect(score.budgetsTotal == 0)
        // recurringPercentOfIncome should be 0 with no recurring series
        #expect(score.recurringPercentOfIncome == 0)
    }
}
