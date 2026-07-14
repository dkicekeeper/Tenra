//
//  InsightsService+Forecasting.swift
//  Tenra
//
//  Spending forecast, balance runway, year-over-year, and income source breakdown.
//

import Foundation
import os
import SwiftUI

extension InsightsService {

    // MARK: - Forecasting Insights

    nonisolated func generateForecastingInsights(
        allTransactions: [Transaction],
        baseCurrency: String,
        snapshot: DataSnapshot,
        filteredTransactions: [Transaction]? = nil,
        preAggregated: PreAggregatedData? = nil,
        skipSharedGenerators: Bool = false
    ) -> [Insight] {
        var insights: [Insight] = []

        // SpendingForecast and YoY are granularity-independent — skip when shared
        // insights already provided. (BalanceRunway merged into EmergencyFund —
        // audit 2026-07: both answered "how many months will the money last".)
        if !skipSharedGenerators {
            if let forecast = generateSpendingForecast(transactions: snapshot.transactions, recurringSeries: snapshot.recurringSeries, categories: snapshot.categories, baseCurrency: baseCurrency, preAggregated: preAggregated) {
                insights.append(forecast)
            }
            if let yoy = generateYearOverYear(transactions: snapshot.transactions, baseCurrency: baseCurrency, preAggregated: preAggregated) {
                insights.append(yoy)
            }
        }
        // IncomeSourceBreakdown is granularity-dependent (uses currentBucketForForecasting) — always compute.
        // Use filteredTransactions (windowed) when available so incomeSourceBreakdown
        // respects the selected granularity period.
        let sourceTransactions = filteredTransactions ?? allTransactions
        if let breakdown = generateIncomeSourceBreakdown(allTransactions: sourceTransactions, categories: snapshot.categories, baseCurrency: baseCurrency) {
            insights.append(breakdown)
        }
        return insights
    }

    // MARK: - Private Forecasting Sub-Generators

    /// Projects month-end spend = avg daily rate × remaining days + pending recurring.
    private nonisolated func generateSpendingForecast(transactions: [Transaction], recurringSeries: [RecurringSeries], categories: [CustomCategory], baseCurrency: String, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        let df = DateFormatters.dateFormatter

        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }

        // Direct in-memory expense sum for last 30 days.
        // This 30-day filter doesn't align to month boundaries, so it can't use preAggregated.
        let last30Spent = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { total, tx in
                guard let txDate = df.date(from: tx.date),
                      txDate >= thirtyDaysAgo, txDate < now else { return total }
                return total + resolveAmount(tx, baseCurrency: baseCurrency)
            }
        let avgDailySpend = last30Spent / 30

        let totalDaysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: now)
        let daysRemaining = totalDaysInMonth - dayOfMonth

        let monthlyRecurringExpenses = recurringSeries
            .filter { $0.isActive }
            .filter { series in
                let isExpense = categories.first { c in c.name == series.category }?.type != .income
                return isExpense
            }
            .reduce(0.0) { total, series in
                guard let startDate = df.date(from: series.startDate) else { return total }
                if startDate > now { return total }
                return total + seriesMonthlyEquivalent(series, baseCurrency: baseCurrency, cache: preAggregated?.seriesMonthlyEquivalents)
            }

        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let currentMonthData: InMemoryMonthlyTotal?
        if let preAggregated {
            currentMonthData = preAggregated.lastMonthlyTotals(1).first
        } else {
            currentMonthData = Self.computeLastMonthlyTotals(1, from: transactions, baseCurrency: baseCurrency).first
        }
        let spentSoFar = currentMonthData?.totalExpenses ?? 0
        let monthlyIncome = currentMonthData?.totalIncome ?? 0

        let pendingRecurring = max(0, (monthlyRecurringExpenses / Double(totalDaysInMonth)) * Double(daysRemaining))
        let projectedRemaining = avgDailySpend * Double(daysRemaining)
        let forecast = spentSoFar + projectedRemaining + pendingRecurring

        let severity: InsightSeverity = monthlyIncome > 0 ? (forecast > monthlyIncome ? .warning : .positive) : .neutral

        let recommendation: String
        if monthlyIncome > 0 && forecast > monthlyIncome {
            let overrun = forecast - monthlyIncome
            recommendation = String(
                format: String(localized: "insights.formula.spendingForecast.rec.overrun"),
                Formatting.formatCurrencySmart(overrun, currency: baseCurrency)
            )
        } else if monthlyIncome > 0 {
            let cushion = monthlyIncome - forecast
            recommendation = String(
                format: String(localized: "insights.formula.spendingForecast.rec.onTrack"),
                Formatting.formatCurrencySmart(cushion, currency: baseCurrency)
            )
        } else {
            recommendation = String(localized: "insights.formula.spendingForecast.rec.noIncome")
        }

        let model = InsightFormulaModel(
            id: "spendingForecast",
            titleKey: "insights.formula.spendingForecast.title",
            icon: "calendar.badge.exclamationmark",
            color: severity.color,
            heroValueText: Formatting.formatCurrencySmart(forecast, currency: baseCurrency),
            heroLabelKey: "insights.formula.spendingForecast.heroLabel",
            formulaHeaderKey: "insights.formula.spendingForecast.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "spentSoFar", labelKey: "insights.formula.spendingForecast.row.spentSoFar", value: spentSoFar, kind: .currency),
                InsightFormulaRow(id: "avgDaily", labelKey: "insights.formula.spendingForecast.row.avgDaily", value: avgDailySpend, kind: .currency),
                InsightFormulaRow(id: "daysLeft", labelKey: "insights.formula.spendingForecast.row.daysLeft", value: Double(daysRemaining), kind: .days),
                InsightFormulaRow(id: "projectedRest", labelKey: "insights.formula.spendingForecast.row.projectedRest", value: projectedRemaining + pendingRecurring, kind: .currency),
                InsightFormulaRow(id: "total", labelKey: "insights.formula.spendingForecast.row.total", value: forecast, kind: .currency, isEmphasised: true)
            ],
            explainerKey: "insights.formula.spendingForecast.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("🔮 [Insights] SpendingForecast — spentSoFar=\(String(format: "%.0f", spentSoFar), privacy: .public), avgDaily=\(String(format: "%.0f", avgDailySpend), privacy: .public), daysLeft=\(daysRemaining), forecast=\(String(format: "%.0f", forecast), privacy: .public) \(baseCurrency, privacy: .public)")
        return Insight(
            id: "spending_forecast",
            type: .spendingForecast,
            title: String(localized: "insights.spendingForecast"),
            subtitle: String(format: "%d " + String(localized: "insights.days") + " " + String(localized: "insights.remaining"), daysRemaining),
            metric: InsightMetric(
                value: forecast,
                formattedValue: Formatting.formatCurrencySmart(forecast, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .forecasting,
            detailData: .formulaBreakdown(model),
            // Fact so far vs projected month total — the projection bar renders
            // translucent + dashed (forecast grammar).
            cardVisual: .barPair(
                previous: spentSoFar,
                current: forecast,
                color: severity == .warning ? AppColors.destructive : AppColors.accent,
                isProjection: true
            )
        )
    }

    /// Compares this month's expenses against the same month last year.
    private nonisolated func generateYearOverYear(transactions: [Transaction], baseCurrency: String, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }

        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let thisMonth: InMemoryMonthlyTotal?
        let lastYear: InMemoryMonthlyTotal?
        if let preAggregated {
            thisMonth = preAggregated.lastMonthlyTotals(1).first
            lastYear = preAggregated.lastMonthlyTotals(1, anchor: oneYearAgo).first
        } else {
            thisMonth = Self.computeLastMonthlyTotals(1, from: transactions, baseCurrency: baseCurrency).first
            lastYear = Self.computeLastMonthlyTotals(1, from: transactions, anchor: oneYearAgo, baseCurrency: baseCurrency).first
        }

        guard let thisExpenses = thisMonth?.totalExpenses,
              let lastYearExpenses = lastYear?.totalExpenses,
              lastYearExpenses > 0 else { return nil }

        let delta = ((thisExpenses - lastYearExpenses) / lastYearExpenses) * 100
        guard abs(delta) > 3 else { return nil }

        let direction: TrendDirection = delta > 0 ? .up : .down
        let severity: InsightSeverity = delta <= -10 ? .positive : (delta >= 15 ? .warning : .neutral)
        let thisLabel = thisMonth?.label ?? ""
        let lastLabel = lastYear?.label ?? ""
        let absDelta = thisExpenses - lastYearExpenses

        let recommendation: String
        if delta <= -10 {
            recommendation = String(localized: "insights.formula.yearOverYear.rec.down")
        } else if delta >= 15 {
            recommendation = String(
                format: String(localized: "insights.formula.yearOverYear.rec.up"),
                String(format: "%.1f%%", delta)
            )
        } else {
            recommendation = String(localized: "insights.formula.yearOverYear.rec.flat")
        }

        let model = InsightFormulaModel(
            id: "yearOverYear",
            titleKey: "insights.formula.yearOverYear.title",
            icon: "calendar.circle.fill",
            color: severity.color,
            heroValueText: String(format: "%+.1f%%", delta),
            heroLabelKey: "insights.formula.yearOverYear.heroLabel",
            formulaHeaderKey: "insights.formula.yearOverYear.formulaHeader",
            formulaRows: [
                // Row label carries the period (e.g. "June 2026"); the value column
                // shows just the amount — instead of cramming "amount — month" into one cell.
                InsightFormulaRow(
                    id: "thisMonth",
                    labelKey: "insights.formula.yearOverYear.row.thisMonth",
                    labelText: thisLabel,
                    value: thisExpenses,
                    kind: .currency
                ),
                InsightFormulaRow(
                    id: "lastYear",
                    labelKey: "insights.formula.yearOverYear.row.lastYear",
                    labelText: lastLabel,
                    value: lastYearExpenses,
                    kind: .currency
                ),
                InsightFormulaRow(id: "absDelta", labelKey: "insights.formula.yearOverYear.row.absDelta", value: absDelta, kind: .currency),
                InsightFormulaRow(id: "delta", labelKey: "insights.formula.yearOverYear.row.delta", value: delta, kind: .percent, isEmphasised: true)
            ],
            explainerKey: "insights.formula.yearOverYear.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("📅 [Insights] YoY — this=\(String(format: "%.0f", thisExpenses), privacy: .public), lastYear=\(String(format: "%.0f", lastYearExpenses), privacy: .public), delta=\(String(format: "%+.1f%%", delta), privacy: .public)")
        return Insight(
            id: "year_over_year",
            type: .yearOverYear,
            title: String(localized: "insights.yearOverYear"),
            subtitle: thisLabel,
            metric: InsightMetric(
                value: thisExpenses,
                formattedValue: Formatting.formatCurrencySmart(thisExpenses, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: delta,
                changeAbsolute: absDelta,
                comparisonPeriod: String(localized: "insights.yearOverYear")
            ),
            severity: severity,
            category: .forecasting,
            detailData: .formulaBreakdown(model),
            cardVisual: .barPair(
                previous: lastYearExpenses,
                current: thisExpenses,
                color: direction == .up ? AppColors.destructive : AppColors.success,
                isProjection: false
            )
        )
    }



    // MARK: - Income Source Breakdown

    /// Groups income transactions by category to show income source distribution.
    nonisolated func generateIncomeSourceBreakdown(allTransactions: [Transaction], categories: [CustomCategory], baseCurrency: String) -> Insight? {
        let incomeCategories = categories.filter { $0.type == .income }
        guard incomeCategories.count >= 2 else { return nil }

        let incomeTransactions = allTransactions.filter { $0.type == .income }
        guard !incomeTransactions.isEmpty else { return nil }
        let totalIncome = incomeTransactions.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        guard totalIncome > 0 else { return nil }
        let grouped = Dictionary(grouping: incomeTransactions, by: { $0.category })
        let breakdownItems: [CategoryBreakdownItem] = grouped
            .map { catName, txns -> CategoryBreakdownItem in
                let amount = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                let pct = (amount / totalIncome) * 100
                let cat = categories.first { $0.name == catName }
                return CategoryBreakdownItem(
                    id: catName,
                    categoryName: catName,
                    amount: amount,
                    percentage: pct,
                    color: Color(hex: cat?.colorHex ?? "#5856D6"),
                    iconSource: cat?.iconSource,
                    subcategories: []
                )
            }
            .sorted { $0.amount > $1.amount }

        guard let top = breakdownItems.first else { return nil }
        let topPercent = top.percentage

        Self.logger.debug("💼 [Insights] IncomeSourceBreakdown — \(breakdownItems.count) sources, top='\(top.categoryName, privacy: .public)' \(String(format: "%.0f%%", topPercent), privacy: .public)")
        return Insight(
            id: "income_source_breakdown",
            type: .incomeSourceBreakdown,
            title: String(localized: "insights.incomeSourceBreakdown"),
            subtitle: top.categoryName,
            metric: InsightMetric(
                value: topPercent,
                formattedValue: String(format: "%.0f%%", topPercent),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .income,
            detailData: .categoryBreakdown(breakdownItems)
        )
    }

}
