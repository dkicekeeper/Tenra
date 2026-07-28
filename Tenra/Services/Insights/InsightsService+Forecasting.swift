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
        skipSharedGenerators: Bool = false,
        granularity: InsightGranularity? = nil,
        periodPoints: [PeriodDataPoint] = [],
        txDateMap: [String: Date]? = nil
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
        // IncomeSourceBreakdown is granularity-dependent — always compute.
        // `filteredTransactions` is the WINDOWED set (whole filter window), not the current
        // bucket: the generator pages across every period and narrows per page itself.
        let sourceTransactions = filteredTransactions ?? allTransactions
        if let breakdown = generateIncomeSourceBreakdown(
            allTransactions: sourceTransactions,
            categories: snapshot.categories,
            baseCurrency: baseCurrency,
            granularity: granularity,
            periodPoints: periodPoints,
            txDateMap: txDateMap
        ) {
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
                guard let txDate = FastDateParser.date(from: tx.date),
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
    ///
    /// Mirrors the paged path of `generateSpendingInsights`: for a finite granularity
    /// it builds one breakdown per period so the detail view can swipe across periods
    /// (current → back to the first transaction's period). `.allTime` — and any case
    /// where no period points were produced — falls back to a single breakdown scoped
    /// to the current bucket.
    ///
    /// `allTransactions` must be the **windowed** set (the whole filter window), not the
    /// current bucket: the pager needs every period, and narrowing happens per page here.
    nonisolated func generateIncomeSourceBreakdown(
        allTransactions: [Transaction],
        categories: [CustomCategory],
        baseCurrency: String,
        granularity: InsightGranularity? = nil,
        periodPoints: [PeriodDataPoint] = [],
        txDateMap: [String: Date]? = nil
    ) -> Insight? {
        let incomeCategories = categories.filter { $0.type == .income }
        guard incomeCategories.count >= 2 else { return nil }

        let incomeTransactions = allTransactions.filter { $0.type == .income }
        guard !incomeTransactions.isEmpty else { return nil }

        // Realized-only, matching the period totals (pt.income) the percentages divide by.
        // Without this a future-dated income in the current bucket inflates the breakdown
        // against its own total — the same bug the spending breakdown had.
        let resolveDate: (Transaction) -> Date? = { tx in
            txDateMap?[tx.date] ?? FastDateParser.date(from: tx.date)
        }

        var categoryByName: [String: CustomCategory] = [:]
        categoryByName.reserveCapacity(categories.count)
        for cat in categories { categoryByName[cat.name] = cat }

        let makeBreakdown: ([Transaction], Double) -> [CategoryBreakdownItem] = { txns, periodTotal in
            Dictionary(grouping: txns, by: { $0.category })
                .map { catName, catTxns -> (key: String, total: Double) in
                    (key: catName, total: catTxns.reduce(0.0) { $0 + self.resolveAmount($1, baseCurrency: baseCurrency) })
                }
                .filter { !$0.key.isEmpty }
                .sorted { $0.total > $1.total }
                .map { item in
                    let cat = categoryByName[item.key]
                    return CategoryBreakdownItem(
                        id: item.key,
                        categoryName: item.key,
                        amount: item.total,
                        percentage: periodTotal > 0 ? (item.total / periodTotal) * 100 : 0,
                        color: Color(hex: cat?.colorHex ?? "#5856D6"),
                        iconSource: cat?.iconSource,
                        subcategories: []
                    )
                }
        }

        // Builds the insight from a top item + the total it's a share of. Shared by both
        // paths so the hero reads identically whether or not the detail is paged.
        let makeInsight: (CategoryBreakdownItem?, Double, String, InsightDetailData) -> Insight? = { top, total, fallbackSubtitle, detail in
            guard let top else {
                // Keep the card when paging: the user can still swipe to a period that
                // has income. Without pages an empty current bucket has nothing to show.
                guard case .categoryBreakdownPaged = detail else { return nil }
                return Insight(
                    id: "income_source_breakdown",
                    type: .incomeSourceBreakdown,
                    title: String(localized: "insights.incomeSourceBreakdown"),
                    subtitle: fallbackSubtitle,
                    metric: InsightMetric(
                        value: 0,
                        formattedValue: String(localized: "insights.noIncome"),
                        currency: nil,
                        unit: nil
                    ),
                    trend: nil,
                    severity: .neutral,
                    category: .income,
                    detailData: detail
                )
            }
            let topPercent = total > 0 ? (top.amount / total) * 100 : 0
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
                detailData: detail
            )
        }

        // ── Paged path ────────────────────────────────────────────────────────
        if let gran = granularity, gran != .allTime, !periodPoints.isEmpty {
            var incomeByKey: [String: [Transaction]] = [:]
            for tx in incomeTransactions {
                guard let d = resolveDate(tx), LedgerPolicyRule.isRealized(d) else { continue }
                incomeByKey[gran.groupingKey(for: d), default: []].append(tx)
            }

            let pages: [PeriodCategoryBreakdown] = periodPoints.map { pt in
                PeriodCategoryBreakdown(
                    id: pt.key,
                    label: gran.headingLabel(for: pt.key),
                    total: pt.income,
                    items: makeBreakdown(incomeByKey[pt.key] ?? [], pt.income)
                )
            }

            let currentKey = gran.currentPeriodKey
            let currentIdx = periodPoints.firstIndex(where: { $0.key == currentKey }) ?? (periodPoints.count - 1)
            let currentPage = pages.indices.contains(currentIdx) ? pages[currentIdx] : pages.last

            Self.logger.debug("💼 [Insights] IncomeSourceBreakdown (paged) — periods=\(pages.count), currentIdx=\(currentIdx), currentTop='\(currentPage?.items.first?.categoryName ?? "—", privacy: .public)'")
            return makeInsight(
                currentPage?.items.first,
                currentPage?.total ?? 0,
                currentPage?.label ?? gran.headingLabel(for: currentKey),
                .categoryBreakdownPaged(CategoryBreakdownPages(periods: pages, currentIndex: currentIdx))
            )
        }

        // ── Fallback: single breakdown ────────────────────────────────────────
        // Scope to the current bucket for a finite granularity that produced no period
        // points; `.allTime` (and no granularity) uses the whole window.
        let scoped: [Transaction]
        if let gran = granularity, gran != .allTime {
            let key = gran.currentPeriodKey
            let start = gran.periodStart(for: key)
            let end = gran.periodEnd(for: key)
            scoped = incomeTransactions.filter { tx in
                guard let d = resolveDate(tx), d >= start, d < end, LedgerPolicyRule.isRealized(d) else { return false }
                return true
            }
        } else {
            scoped = incomeTransactions.filter { tx in
                guard let d = resolveDate(tx) else { return false }
                return LedgerPolicyRule.isRealized(d)
            }
        }

        let totalIncome = scoped.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        guard totalIncome > 0 else { return nil }
        let breakdownItems = makeBreakdown(scoped, totalIncome)
        guard let top = breakdownItems.first else { return nil }

        Self.logger.debug("💼 [Insights] IncomeSourceBreakdown — \(breakdownItems.count) sources, top='\(top.categoryName, privacy: .public)' \(String(format: "%.0f%%", top.percentage), privacy: .public)")
        return makeInsight(top, totalIncome, top.categoryName, .categoryBreakdown(breakdownItems))
    }

}
