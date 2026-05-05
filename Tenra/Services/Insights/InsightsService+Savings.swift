//
//  InsightsService+Savings.swift
//  Tenra
//
//  Savings rate and emergency fund coverage insights.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Savings Insights

    nonisolated func generateSavingsInsights(
        allIncome: Double,
        allExpenses: Double,
        bucketLabel: String = "",
        baseCurrency: String,
        balanceFor: (String) -> Double,
        accounts: [Account],
        transactions: [Transaction],
        preAggregated: PreAggregatedData? = nil,
        skipSharedGenerators: Bool = false
    ) -> [Insight] {
        var insights: [Insight] = []

        // SavingsRate is granularity-dependent (uses bucket income/expenses) — always compute
        if let rate = generateSavingsRate(allIncome: allIncome, allExpenses: allExpenses, bucketLabel: bucketLabel, baseCurrency: baseCurrency) {
            insights.append(rate)
        }
        // EmergencyFund is granularity-independent — skip when shared provided
        if !skipSharedGenerators {
            if let fund = generateEmergencyFund(accounts: accounts, transactions: transactions, baseCurrency: baseCurrency, balanceFor: balanceFor, preAggregated: preAggregated) {
                insights.append(fund)
            }
        }
        return insights
    }

    // MARK: - Private Savings Sub-Generators

    private nonisolated func generateSavingsRate(allIncome: Double, allExpenses: Double, bucketLabel: String, baseCurrency: String) -> Insight? {
        guard allIncome > 0 else { return nil }
        let rate = ((allIncome - allExpenses) / allIncome) * 100
        let savedAmount = allIncome - allExpenses
        let severity: InsightSeverity = rate > 20 ? .positive : (rate >= 10 ? .warning : .critical)
        let periodSuffix: String = bucketLabel.isEmpty ? "" : " — " + bucketLabel

        let recommendation: String
        if rate >= 20 {
            recommendation = String(localized: "insights.formula.savingsRate.rec.good")
        } else if rate >= 10 {
            let target = allIncome * 0.20
            let gap = target - savedAmount
            recommendation = String(
                format: String(localized: "insights.formula.savingsRate.rec.fair"),
                Formatting.formatCurrencySmart(max(0, gap), currency: baseCurrency)
            )
        } else {
            let target = allIncome * 0.10
            let gap = target - savedAmount
            recommendation = String(
                format: String(localized: "insights.formula.savingsRate.rec.low"),
                Formatting.formatCurrencySmart(max(0, gap), currency: baseCurrency)
            )
        }

        let model = InsightFormulaModel(
            id: "savingsRate",
            titleKey: "insights.formula.savingsRate.title",
            icon: "banknote.fill",
            color: severity.color,
            heroValueText: String(format: "%.1f%%", rate),
            heroLabelKey: "insights.formula.savingsRate.heroLabel",
            formulaHeaderKey: "insights.formula.savingsRate.formulaHeader",
            formulaRows: [
                InsightFormulaRow(
                    id: "period",
                    labelKey: "insights.formula.savingsRate.row.period",
                    value: 0,
                    kind: .rawText(bucketLabel.isEmpty ? String(localized: "insights.granularity.allTime") : bucketLabel)
                ),
                InsightFormulaRow(id: "income", labelKey: "insights.formula.savingsRate.row.income", value: allIncome, kind: .currency),
                InsightFormulaRow(id: "expenses", labelKey: "insights.formula.savingsRate.row.expenses", value: allExpenses, kind: .currency),
                InsightFormulaRow(id: "saved", labelKey: "insights.formula.savingsRate.row.saved", value: max(0, savedAmount), kind: .currency),
                InsightFormulaRow(id: "rate", labelKey: "insights.formula.savingsRate.row.rate", value: rate, kind: .percent, isEmphasised: true)
            ],
            explainerKey: "insights.formula.savingsRate.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("💰 [Insights] SavingsRate — \(String(format: "%.1f%%", rate), privacy: .public), severity=\(String(describing: severity), privacy: .public), bucket=\(bucketLabel, privacy: .public)")
        return Insight(
            id: "savings_rate",
            type: .savingsRate,
            title: String(localized: "insights.savingsRate"),
            subtitle: Formatting.formatCurrencySmart(max(0, savedAmount), currency: baseCurrency) + periodSuffix,
            metric: InsightMetric(
                value: rate,
                formattedValue: String(format: "%.1f%%", rate),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: .formulaBreakdown(model)
        )
    }

    private nonisolated func generateEmergencyFund(accounts: [Account], transactions: [Transaction], baseCurrency: String, balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil) -> Insight? {
        // Loans are liabilities, not emergency reserves.
        let totalBalance = accounts.filter { !$0.isLoan }.reduce(0.0) { $0 + balanceFor($1.id) }
        guard totalBalance > 0 else { return nil }

        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let aggregates: [InMemoryMonthlyTotal]
        if let preAggregated {
            aggregates = preAggregated.lastMonthlyTotals(3)
        } else {
            aggregates = Self.computeLastMonthlyTotals(3, from: transactions, baseCurrency: baseCurrency)
        }
        guard !aggregates.isEmpty else { return nil }

        let avgMonthlyExpenses = aggregates.reduce(0.0) { $0 + $1.totalExpenses } / Double(aggregates.count)
        guard avgMonthlyExpenses > 0 else { return nil }

        let monthsCovered = totalBalance / avgMonthlyExpenses
        let severity: InsightSeverity = monthsCovered >= 3 ? .positive : (monthsCovered >= 1 ? .warning : .critical)
        let monthsInt = Int(monthsCovered.rounded(.down))

        let recommendation: String
        if monthsCovered >= 3 {
            recommendation = String(localized: "insights.formula.emergencyFund.rec.good")
        } else {
            let targetBalance = avgMonthlyExpenses * 3
            let gap = targetBalance - totalBalance
            recommendation = String(
                format: String(localized: "insights.formula.emergencyFund.rec.gap"),
                Formatting.formatCurrencySmart(max(0, gap), currency: baseCurrency)
            )
        }

        let model = InsightFormulaModel(
            id: "emergencyFund",
            titleKey: "insights.formula.emergencyFund.title",
            icon: "shield.lefthalf.filled",
            color: severity.color,
            heroValueText: String(format: String(localized: "insights.formula.value.months"), monthsCovered),
            heroLabelKey: "insights.formula.emergencyFund.heroLabel",
            formulaHeaderKey: "insights.formula.emergencyFund.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "balance", labelKey: "insights.formula.emergencyFund.row.balance", value: totalBalance, kind: .currency),
                InsightFormulaRow(id: "avgExpenses", labelKey: "insights.formula.emergencyFund.row.avgExpenses", value: avgMonthlyExpenses, kind: .currency),
                InsightFormulaRow(id: "monthsCovered", labelKey: "insights.formula.emergencyFund.row.monthsCovered", value: monthsCovered, kind: .months, isEmphasised: true)
            ],
            explainerKey: "insights.formula.emergencyFund.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

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
            detailData: .formulaBreakdown(model)
        )
    }

}
