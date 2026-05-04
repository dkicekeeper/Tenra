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
        #expect(score.monthsInWindow == 0)
    }
}
