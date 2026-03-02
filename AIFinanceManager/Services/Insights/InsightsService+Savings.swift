//
//  InsightsService+Savings.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: savings rate, emergency fund coverage, savings momentum trend.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Savings Insights (Phase 24)

    func generateSavingsInsights(
        allIncome: Double,
        allExpenses: Double,
        baseCurrency: String,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        var insights: [Insight] = []

        if let rate = generateSavingsRate(allIncome: allIncome, allExpenses: allExpenses, baseCurrency: baseCurrency) {
            insights.append(rate)
        }
        if let fund = generateEmergencyFund(baseCurrency: baseCurrency, balanceFor: balanceFor) {
            insights.append(fund)
        }
        if let momentum = generateSavingsMomentum(baseCurrency: baseCurrency) {
            insights.append(momentum)
        }
        return insights
    }

    // MARK: - Private Savings Sub-Generators

    private func generateSavingsRate(allIncome: Double, allExpenses: Double, baseCurrency: String) -> Insight? {
        guard allIncome > 0 else { return nil }
        let rate = ((allIncome - allExpenses) / allIncome) * 100
        let savedAmount = allIncome - allExpenses
        let severity: InsightSeverity = rate > 20 ? .positive : (rate >= 10 ? .warning : .critical)
        Self.logger.debug("💰 [Insights] SavingsRate — \(String(format: "%.1f%%", rate), privacy: .public), severity=\(String(describing: severity), privacy: .public)")
        return Insight(
            id: "savings_rate",
            type: .savingsRate,
            title: String(localized: "insights.savingsRate"),
            subtitle: Formatting.formatCurrencySmart(max(0, savedAmount), currency: baseCurrency),
            metric: InsightMetric(
                value: rate,
                formattedValue: String(format: "%.1f%%", rate),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: nil
        )
    }

    @MainActor
    private func generateEmergencyFund(baseCurrency: String, balanceFor: (String) -> Double) -> Insight? {
        let totalBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard totalBalance > 0 else { return nil }

        // Phase 40: In-memory 3-month average replaces MonthlyAggregateService.fetchLast()
        let aggregates = Self.computeLastMonthlyTotals(3, from: transactionStore.transactions, baseCurrency: baseCurrency)
        guard !aggregates.isEmpty else { return nil }

        let avgMonthlyExpenses = aggregates.reduce(0.0) { $0 + $1.totalExpenses } / Double(aggregates.count)
        guard avgMonthlyExpenses > 0 else { return nil }

        let monthsCovered = totalBalance / avgMonthlyExpenses
        let severity: InsightSeverity = monthsCovered >= 3 ? .positive : (monthsCovered >= 1 ? .warning : .critical)
        let monthsInt = Int(monthsCovered.rounded(.down))
        Self.logger.debug("🛡 [Insights] EmergencyFund — \(String(format: "%.1f", monthsCovered), privacy: .public) months, severity=\(String(describing: severity), privacy: .public)")
        return Insight(
            id: "emergency_fund",
            type: .emergencyFund,
            title: String(localized: "insights.emergencyFund"),
            subtitle: String(format: String(localized: "insights.monthsCovered"), monthsInt),
            metric: InsightMetric(
                value: monthsCovered,
                formattedValue: String(format: "%.1f", monthsCovered),
                currency: nil,
                unit: String(localized: "insights.months")
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: nil
        )
    }

    @MainActor
    private func generateSavingsMomentum(baseCurrency: String) -> Insight? {
        // Phase 40: In-memory computation replaces MonthlyAggregateService.fetchLast()
        let aggregates = Self.computeLastMonthlyTotals(4, from: transactionStore.transactions, baseCurrency: baseCurrency)
        guard aggregates.count >= 2 else { return nil }

        let rates: [Double] = aggregates.map { agg in
            guard agg.totalIncome > 0 else { return 0 }
            return ((agg.totalIncome - agg.totalExpenses) / agg.totalIncome) * 100
        }

        guard let currentRate = rates.last else { return nil }
        let prevRates = Array(rates.dropLast())
        guard !prevRates.isEmpty else { return nil }

        let avgPrevRate = prevRates.reduce(0.0, +) / Double(prevRates.count)
        let delta = currentRate - avgPrevRate
        guard abs(delta) > 1 else { return nil }

        let direction: TrendDirection = delta > 0 ? .up : .down
        let severity: InsightSeverity = delta > 2 ? .positive : (delta < -2 ? .warning : .neutral)
        Self.logger.debug("📊 [Insights] SavingsMomentum — current=\(String(format: "%.1f%%", currentRate), privacy: .public), avgPrev=\(String(format: "%.1f%%", avgPrevRate), privacy: .public), delta=\(String(format: "%+.1f%%", delta), privacy: .public)")
        return Insight(
            id: "savings_momentum",
            type: .savingsMomentum,
            title: String(localized: "insights.savingsMomentum"),
            subtitle: String(localized: "insights.vsPrevious3Months"),
            metric: InsightMetric(
                value: currentRate,
                formattedValue: String(format: "%.1f%%", currentRate),
                currency: nil,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: delta,
                changeAbsolute: nil,
                comparisonPeriod: String(localized: "insights.vsPrevious3Months")
            ),
            severity: severity,
            category: .savings,
            detailData: nil
        )
    }
}
