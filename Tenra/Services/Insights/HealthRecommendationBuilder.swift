//
//  HealthRecommendationBuilder.swift
//  Tenra
//
//  Pure functions: FinancialHealthScore raw values → localized recommendation copy.
//  One method per component. No I/O, no actor isolation, easy to unit-test.
//

import Foundation

nonisolated enum HealthRecommendationBuilder {

    // MARK: - Savings Rate

    static func savingsRateRecommendation(_ score: FinancialHealthScore) -> String {
        if score.savingsRatePercent >= 20 {
            return String(localized: "insights.health.rec.savingsRate.healthy")
        }

        let targetIncomeMinusExpense = 0.20 * score.totalIncomeWindow
        let currentDelta = score.totalIncomeWindow - score.totalExpensesWindow
        let gap = max(0, targetIncomeMinusExpense - currentDelta)

        // The user can close the gap by either cutting expenses by `gap`
        // or growing income enough that 20% of the new income equals the
        // new gap. Income-grow target = gap / (1 − 0.20) = gap / 0.8.
        let cutExpenses = Formatting.formatCurrencySmart(gap, currency: score.baseCurrency)
        let growIncome  = Formatting.formatCurrencySmart(gap / 0.8, currency: score.baseCurrency)

        let format = String(localized: "insights.health.rec.savingsRate.below")
        return String(format: format, cutExpenses, growIncome)
    }

    // MARK: - Budget Adherence

    static func budgetAdherenceRecommendation(_ score: FinancialHealthScore) -> String {
        if score.budgetsTotal == 0 {
            return String(localized: "insights.health.rec.budgetAdherence.empty")
        }
        let over = score.budgetsTotal - score.budgetsOnTrack
        if over == 0 {
            return String(localized: "insights.health.rec.budgetAdherence.full")
        }
        let format = String(localized: "insights.health.rec.budgetAdherence.partial")
        return String(format: format, over)
    }

    // MARK: - Recurring Ratio

    static func recurringRatioRecommendation(_ score: FinancialHealthScore) -> String {
        let key: String = score.recurringPercentOfIncome > 50
            ? "insights.health.rec.recurringRatio.high"
            : "insights.health.rec.recurringRatio.healthy"
        let format = String(localized: String.LocalizationValue(key))
        return String(format: format, score.recurringPercentOfIncome)
    }

    // MARK: - Emergency Fund

    static func emergencyFundRecommendation(_ score: FinancialHealthScore) -> String {
        if score.monthsCovered >= 3 {
            let format = String(localized: "insights.health.rec.emergencyFund.healthy")
            return String(format: format, score.monthsCovered)
        }

        let targetBalance = 3.0 * score.avgMonthlyExpenses
        let gap = max(0, targetBalance - score.totalBalance)
        let gapFormatted = Formatting.formatCurrencySmart(gap, currency: score.baseCurrency)

        if score.avgMonthlyNetFlow > 0 {
            let monthsToTarget = gap / score.avgMonthlyNetFlow
            let format = String(localized: "insights.health.rec.emergencyFund.belowWithProjection")
            return String(format: format, gapFormatted, monthsToTarget)
        }

        let format = String(localized: "insights.health.rec.emergencyFund.below")
        return String(format: format, gapFormatted)
    }

    // MARK: - Cash Flow

    static func cashFlowRecommendation(_ score: FinancialHealthScore) -> String {
        if score.netFlowPercent >= 0 {
            let format = String(localized: "insights.health.rec.cashFlow.positive")
            return String(format: format, score.netFlowPercent)
        }
        let format = String(localized: "insights.health.rec.cashFlow.negative")
        return String(format: format, abs(score.netFlowPercent))
    }
}
