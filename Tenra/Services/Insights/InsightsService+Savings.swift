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
        baseCurrency: String,
        balanceFor: (String) -> Double,
        accounts: [Account],
        transactions: [Transaction],
        preAggregated: PreAggregatedData? = nil,
        skipSharedGenerators: Bool = false
    ) -> [Insight] {
        var insights: [Insight] = []

        // SavingsRate uses the LAST COMPLETED calendar month rather than the current
        // (partial) period: salary commonly lands at month-end, so mid-month the rate
        // would always read as a deficit. The completed month is a full income+expense
        // cycle, making the metric meaningful regardless of the selected granularity.
        let calendar = Calendar.current
        let prevMonthAnchor = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let completedMonth: InMemoryMonthlyTotal?
        if let preAggregated {
            completedMonth = preAggregated.lastMonthlyTotals(1, anchor: prevMonthAnchor).first
        } else {
            completedMonth = Self.computeLastMonthlyTotals(1, from: transactions, anchor: prevMonthAnchor, baseCurrency: baseCurrency).first
        }
        if let completedMonth,
           let rate = generateSavingsRate(allIncome: completedMonth.totalIncome, allExpenses: completedMonth.totalExpenses, bucketLabel: completedMonth.label, baseCurrency: baseCurrency) {
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
            detailData: .formulaBreakdown(model),
            // Gauge vs the classic 20% target; a deficit (rate ≤ 0) has nothing
            // to gauge — leave nil so the card takes full width.
            cardVisual: rate > 0
                ? .halfGauge(value: rate, norm: 20, color: severity.color)
                : nil
        )
    }

    private nonisolated func generateEmergencyFund(accounts: [Account], transactions: [Transaction], baseCurrency: String, balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil) -> Insight? {
        // Loans are liabilities, not emergency reserves.
        let totalBalance = accounts.filter { !$0.isLoan && $0.includeInBalance }.reduce(0.0) { $0 + balanceFor($1.id) }
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
        let fundSeverity: InsightSeverity = monthsCovered >= 3 ? .positive : (monthsCovered >= 1 ? .warning : .critical)
        let monthsInt = Int(monthsCovered.rounded(.down))

        // Runway at the current burn rate (merged from the former balanceRunway
        // insight — audit 2026-07). "If income stopped" (monthsCovered) and
        // "at the current pace" (runway) now live in one card.
        let avgMonthlyIncome = aggregates.reduce(0.0) { $0 + $1.totalIncome } / Double(aggregates.count)
        let avgMonthlyNetFlow = avgMonthlyIncome - avgMonthlyExpenses
        let runway: Double? = avgMonthlyNetFlow < 0 ? totalBalance / abs(avgMonthlyNetFlow) : nil
        // A negative net flow shortens the real horizon — surface the worse of the two.
        let runwaySeverity: InsightSeverity? = runway.map { $0 >= 3 ? .positive : ($0 >= 1 ? .warning : .critical) }
        let severity: InsightSeverity = {
            guard let runwaySeverity else { return fundSeverity }
            return runwaySeverity.sortOrder < fundSeverity.sortOrder ? runwaySeverity : fundSeverity
        }()

        let recommendation: String
        if let runway, runway < 1 {
            recommendation = String(localized: "insights.formula.balanceRunway.rec.critical")
        } else if monthsCovered >= 3 {
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
            formulaRows: {
                var rows = [
                    InsightFormulaRow(id: "balance", labelKey: "insights.formula.emergencyFund.row.balance", value: totalBalance, kind: .currency),
                    InsightFormulaRow(id: "avgExpenses", labelKey: "insights.formula.emergencyFund.row.avgExpenses", value: avgMonthlyExpenses, kind: .currency),
                    InsightFormulaRow(id: "monthsCovered", labelKey: "insights.formula.emergencyFund.row.monthsCovered", value: monthsCovered, kind: .months, isEmphasised: true)
                ]
                // Reuse the former balanceRunway row keys — they exist in all locales.
                rows.append(InsightFormulaRow(id: "netFlow", labelKey: "insights.formula.balanceRunway.row.netFlow", value: avgMonthlyNetFlow, kind: .currency))
                if let runway {
                    rows.append(InsightFormulaRow(id: "runway", labelKey: "insights.formula.balanceRunway.row.runway", value: runway, kind: .months, isEmphasised: true))
                }
                return rows
            }(),
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
            detailData: .formulaBreakdown(model),
            // Discrete milestone scale: months covered out of 6, target tick at
            // the 3-month baseline (same baseline the health score uses).
            cardVisual: .milestoneGauge(
                value: monthsCovered,
                target: 3,
                maxValue: 6,
                color: severity.color
            )
        )
    }

}
