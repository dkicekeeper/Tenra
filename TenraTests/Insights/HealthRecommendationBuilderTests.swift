//
//  HealthRecommendationBuilderTests.swift
//  TenraTests
//

import Testing
import Foundation
import SwiftUI
@testable import Tenra

struct HealthRecommendationBuilderTests {

    private func make(
        savingsRatePercent: Double = 0,
        budgetsOnTrack: Int = 0,
        budgetsTotal: Int = 0,
        recurringMonthlyTotal: Double = 0,
        recurringPercentOfIncome: Double = 0,
        monthsCovered: Double = 0,
        avgMonthlyExpenses: Double = 0,
        avgMonthlyNetFlow: Double = 0,
        totalBalance: Double = 0,
        netFlowPercent: Double = 0,
        totalIncomeWindow: Double = 0,
        totalExpensesWindow: Double = 0,
        isBudgetComponentActive: Bool = true,
        monthsInWindow: Int = 1
    ) -> FinancialHealthScore {
        FinancialHealthScore(
            score: 50, grade: "Fair", gradeColor: .gray,
            savingsRateScore: 50, budgetAdherenceScore: 50, recurringRatioScore: 50,
            emergencyFundScore: 50, cashflowScore: 50,
            savingsRatePercent: savingsRatePercent,
            budgetsOnTrack: budgetsOnTrack,
            budgetsTotal: budgetsTotal,
            recurringMonthlyTotal: recurringMonthlyTotal,
            recurringPercentOfIncome: recurringPercentOfIncome,
            monthsCovered: monthsCovered,
            avgMonthlyExpenses: avgMonthlyExpenses,
            avgMonthlyNetFlow: avgMonthlyNetFlow,
            totalBalance: totalBalance,
            netFlowPercent: netFlowPercent,
            totalIncomeWindow: totalIncomeWindow,
            totalExpensesWindow: totalExpensesWindow,
            baseCurrency: "KZT",
            isBudgetComponentActive: isBudgetComponentActive,
            monthsInWindow: monthsInWindow
        )
    }

    // MARK: - Savings Rate

    @Test("savingsRate ≥ 20% returns healthy copy")
    func testSavingsRateHealthy() {
        let score = make(savingsRatePercent: 25, totalIncomeWindow: 600_000, totalExpensesWindow: 450_000)
        let text = HealthRecommendationBuilder.savingsRateRecommendation(score)
        let expected = String(localized: "insights.health.rec.savingsRate.healthy")
        #expect(text == expected)
    }

    @Test("savingsRate < 20% returns below-target copy with both deltas")
    func testSavingsRateBelow() {
        let score = make(savingsRatePercent: 10, totalIncomeWindow: 600_000, totalExpensesWindow: 540_000)
        let text = HealthRecommendationBuilder.savingsRateRecommendation(score)
        // Must mention currency and not be the healthy string
        #expect(text.contains("KZT") || text.contains("₸"))
        #expect(text != String(localized: "insights.health.rec.savingsRate.healthy"))
    }

    // Regression: a 12-month window quoted the cumulative gap (e.g. 30M ₸)
    // as "per month". Numbers must be normalised by `monthsInWindow`.
    @Test("savingsRate below-target divides gap by monthsInWindow")
    func testSavingsRateBelowDividesByMonths() {
        // 12-month window: income 7.2M, expenses 6.48M → savings rate 10%.
        // Cumulative gap = 0.20·7.2M − 0.72M = 0.72M. Per-month cut ≈ 60k.
        let score = make(
            savingsRatePercent: 10,
            totalIncomeWindow: 7_200_000,
            totalExpensesWindow: 6_480_000,
            monthsInWindow: 12
        )
        let text = HealthRecommendationBuilder.savingsRateRecommendation(score)
        // Result must include a 60k-style per-month figure, never 720k.
        #expect(text.contains("60") && !text.contains("720 000"))
    }

    // MARK: - Budget Adherence

    @Test("budgetAdherence with no budgets returns empty-state copy")
    func testBudgetAdherenceEmpty() {
        let score = make(budgetsOnTrack: 0, budgetsTotal: 0, isBudgetComponentActive: false)
        let text = HealthRecommendationBuilder.budgetAdherenceRecommendation(score)
        #expect(text == String(localized: "insights.health.rec.budgetAdherence.empty"))
    }

    @Test("budgetAdherence all on track returns full copy")
    func testBudgetAdherenceFull() {
        let score = make(budgetsOnTrack: 5, budgetsTotal: 5)
        let text = HealthRecommendationBuilder.budgetAdherenceRecommendation(score)
        #expect(text == String(localized: "insights.health.rec.budgetAdherence.full"))
    }

    @Test("budgetAdherence partial mentions number of over-budget categories")
    func testBudgetAdherencePartial() {
        let score = make(budgetsOnTrack: 3, budgetsTotal: 7)
        let text = HealthRecommendationBuilder.budgetAdherenceRecommendation(score)
        // 7 - 3 = 4 categories over budget
        #expect(text.contains("4"))
    }

    // MARK: - Recurring Ratio

    @Test("recurringRatio > 50% returns high-share copy")
    func testRecurringRatioHigh() {
        let score = make(recurringPercentOfIncome: 60)
        let text = HealthRecommendationBuilder.recurringRatioRecommendation(score)
        #expect(text.contains("60"))
        #expect(text != String(format: String(localized: "insights.health.rec.recurringRatio.healthy"), 60.0))
    }

    @Test("recurringRatio ≤ 50% returns healthy copy")
    func testRecurringRatioHealthy() {
        let score = make(recurringPercentOfIncome: 35)
        let text = HealthRecommendationBuilder.recurringRatioRecommendation(score)
        #expect(text.contains("35"))
        #expect(text != String(format: String(localized: "insights.health.rec.recurringRatio.high"), 35.0))
    }

    // MARK: - Emergency Fund

    @Test("emergencyFund ≥ 3 months returns healthy copy with month count")
    func testEmergencyFundHealthy() {
        let score = make(monthsCovered: 4.5, avgMonthlyExpenses: 100_000, totalBalance: 450_000)
        let text = HealthRecommendationBuilder.emergencyFundRecommendation(score)
        #expect(text.contains("4.5") || text.contains("4,5"))
    }

    @Test("emergencyFund below target with positive net flow shows projection")
    func testEmergencyFundBelowWithProjection() {
        // 3 months target = 300k; balance 100k → gap 200k. Net flow +50k/mo → 4 months.
        let score = make(monthsCovered: 1, avgMonthlyExpenses: 100_000,
                         avgMonthlyNetFlow: 50_000, totalBalance: 100_000)
        let text = HealthRecommendationBuilder.emergencyFundRecommendation(score)
        let plainBelow = String(format: String(localized: "insights.health.rec.emergencyFund.below"), "—")
        #expect(text != plainBelow)
        // Must contain "4" (months to target, formatted as %.1f → "4.0" or "4,0")
        #expect(text.contains("4.0") || text.contains("4,0"))
    }

    @Test("emergencyFund below target with non-positive net flow omits projection")
    func testEmergencyFundBelowNoProjection() {
        let score = make(monthsCovered: 1, avgMonthlyExpenses: 100_000,
                         avgMonthlyNetFlow: -10_000, totalBalance: 100_000)
        let text = HealthRecommendationBuilder.emergencyFundRecommendation(score)
        // Distinctive phrasing of the projection branch in either locale
        #expect(!text.contains("at your current") && !text.contains("При текущей"))
    }

    // MARK: - Cash Flow

    @Test("cashFlow with positive net flow returns positive copy")
    func testCashFlowPositive() {
        let score = make(netFlowPercent: 12.5)
        let text = HealthRecommendationBuilder.cashFlowRecommendation(score)
        #expect(text.contains("12.5") || text.contains("12,5"))
    }

    @Test("cashFlow with negative net flow returns negative copy with absolute value")
    func testCashFlowNegative() {
        let score = make(netFlowPercent: -8.2)
        let text = HealthRecommendationBuilder.cashFlowRecommendation(score)
        // Format substitutes abs value, so "8.2" should appear (no leading minus)
        #expect(text.contains("8.2") || text.contains("8,2"))
    }
}
