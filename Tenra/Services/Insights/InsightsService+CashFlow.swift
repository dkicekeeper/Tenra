//
//  InsightsService+CashFlow.swift
//  Tenra
//

import Foundation
import os

extension InsightsService {

    // MARK: - Cash Flow Insights

    nonisolated func generateCashFlowInsights(
        allTransactions: [Transaction],
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        snapshot: DataSnapshot
    ) -> [Insight] {
        // Choose number of months based on the selected filter preset:
        // "Last Year" / "All Time" → 12 months; anything shorter → 6 months.
        let trendMonths: Int
        switch timeFilter.preset {
        case .lastYear, .allTime:
            trendMonths = 12
        default:
            trendMonths = 6
        }

        Self.logger.debug("💸 [Insights] CashFlow START — computing \(trendMonths)-month trend")

        // Bug 1 fix: use the filter's INCLUSIVE end as anchor so historical filters produce
        // month points within their period. timeFilter.dateRange().end is EXCLUSIVE.
        let filterEndExclusive = timeFilter.dateRange().end
        let calendar = Calendar.current
        let anchorDate: Date
        if Calendar.current.isDateInToday(filterEndExclusive) || filterEndExclusive > Date() {
            anchorDate = Date()
        } else {
            anchorDate = calendar.date(byAdding: .second, value: -1, to: filterEndExclusive) ?? filterEndExclusive
        }
        guard let windowStart = calendar.date(byAdding: .month, value: -trendMonths, to: startOfMonth(calendar, for: anchorDate)) else {
            Self.logger.debug("💸 [Insights] CashFlow — SKIPPED (could not compute \(trendMonths)-month window)")
            return []
        }
        let windowTransactions = filterService.filterByTimeRange(allTransactions, start: windowStart, end: filterEndExclusive)
        Self.logger.debug("💸 [Insights] CashFlow — \(trendMonths)-month window \(Self.monthYearFormatter.string(from: windowStart), privacy: .public) → \(Self.monthYearFormatter.string(from: anchorDate), privacy: .public) (anchor), transactions=\(windowTransactions.count) (was \(allTransactions.count))")

        let periodData = computeMonthlyPeriodDataPoints(
            transactions: windowTransactions,
            months: trendMonths,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            anchorDate: anchorDate
        )
        guard periodData.count >= 2 else {
            Self.logger.debug("💸 [Insights] CashFlow — SKIPPED (only \(periodData.count) month(s) of data, need ≥2)")
            return []
        }

        var insights: [Insight] = []

        // 1. Net cash flow trend
        if let latest = periodData.last {
            let avgNetFlow = periodData.reduce(0.0) { $0 + $1.netFlow } / Double(periodData.count)
            let severity: InsightSeverity = latest.netFlow > 0 ? .positive : (latest.netFlow < 0 ? .critical : .neutral)
            Self.logger.debug("💸 [Insights] Net cash flow — latest=\(String(format: "%.0f", latest.netFlow), privacy: .public), avg=\(String(format: "%.0f", avgNetFlow), privacy: .public), severity=\(String(describing: severity), privacy: .public)")

            insights.append(Insight(
                id: "net_cashflow",
                type: .netCashFlow,
                title: String(localized: "insights.netCashFlow"),
                subtitle: latest.label,
                metric: InsightMetric(
                    value: latest.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(latest.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: latest.netFlow > avgNetFlow ? .up : (latest.netFlow < avgNetFlow ? .down : .flat),
                    changePercent: nil,
                    changeAbsolute: latest.netFlow - avgNetFlow,
                    comparisonPeriod: String(localized: "insights.vsAverage")
                ),
                severity: severity,
                category: .cashFlow,
                detailData: .periodTrend(periodData)
            ))
        }

        // 2. Period records (merged best + worst — audit 2026-07: two retrospective
        // cards collapsed into one; the detail view lists both rankings)
        if let best = periodData.max(by: { $0.netFlow < $1.netFlow }) {
            insights.append(Insight(
                id: "period_records",
                type: .bestMonth,
                title: String(localized: "insights.periodRecords"),
                subtitle: best.label,
                metric: InsightMetric(
                    value: best.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(best.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .neutral,
                category: .cashFlow,
                detailData: .periodTrend(periodData)
            ))
        }

        // 3. Projected balance (30 days ahead) — show recurring impact delta
        // Loans are liabilities — exclude from "current balance" so projections stay truthful.
        let currentBalance = snapshot.accounts.filter { !$0.isLoan && $0.includeInBalance }.reduce(0.0) { $0 + snapshot.balanceFor($1.id) }
        let recurringNet = monthlyRecurringNet(baseCurrency: baseCurrency, recurringSeries: snapshot.recurringSeries, categories: snapshot.categories)
        let projectedBalance = currentBalance + recurringNet

        let accountCount = snapshot.accounts.count
        Self.logger.debug("💸 [Insights] Projected balance — accounts=\(accountCount), currentBalance=\(String(format: "%.0f", currentBalance), privacy: .public), recurringNet=\(String(format: "%+.0f", recurringNet), privacy: .public), projected=\(String(format: "%.0f", projectedBalance), privacy: .public) \(baseCurrency, privacy: .public)")

        let projectedMetricFormatted: String
        if recurringNet >= 0 {
            projectedMetricFormatted = "+" + Formatting.formatCurrencySmart(recurringNet, currency: baseCurrency)
        } else {
            projectedMetricFormatted = Formatting.formatCurrencySmart(recurringNet, currency: baseCurrency)
        }

        insights.append(Insight(
            id: "projected_balance",
            type: .projectedBalance,
            title: String(localized: "insights.projectedBalance"),
            subtitle: String(localized: "insights.in30Days"),
            metric: InsightMetric(
                value: recurringNet,
                formattedValue: projectedMetricFormatted,
                currency: baseCurrency,
                unit: String(localized: "insights.perMonth")
            ),
            trend: InsightTrend(
                direction: recurringNet >= 0 ? .up : .down,
                changePercent: currentBalance > 0 ? (recurringNet / currentBalance) * 100 : nil,
                changeAbsolute: recurringNet,
                comparisonPeriod: String(localized: "insights.currentBalance") + ": "
                    + Formatting.formatCurrencySmart(currentBalance, currency: baseCurrency)
            ),
            severity: projectedBalance >= 0 ? .positive : .critical,
            category: .cashFlow,
            detailData: nil
        ))

        Self.logger.debug("💸 [Insights] CashFlow END — \(insights.count) insights generated")
        return insights
    }

    // MARK: - Cash Flow from Period Points

    nonisolated func generateCashFlowInsightsFromPeriodPoints(
        periodPoints: [PeriodDataPoint],
        allTransactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        snapshot: DataSnapshot
    ) -> [Insight] {
        guard periodPoints.count >= 2 else { return [] }

        var insights: [Insight] = []
        let currentKey = granularity.currentPeriodKey
        let latest = periodPoints.last(where: { $0.key == currentKey }) ?? periodPoints.last!
        let avgNetFlow = periodPoints.reduce(0.0) { $0 + $1.netFlow } / Double(periodPoints.count)

        // 1. Net cash flow trend
        let severity: InsightSeverity = latest.netFlow > 0 ? .positive : (latest.netFlow < 0 ? .critical : .neutral)
        insights.append(Insight(
            id: "net_cashflow",
            type: .netCashFlow,
            title: String(localized: "insights.netCashFlow"),
            subtitle: latest.label,
            metric: InsightMetric(
                value: latest.netFlow,
                formattedValue: Formatting.formatCurrencySmart(latest.netFlow, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: latest.netFlow > avgNetFlow ? .up : (latest.netFlow < avgNetFlow ? .down : .flat),
                changePercent: nil,
                changeAbsolute: latest.netFlow - avgNetFlow,
                comparisonPeriod: String(localized: "insights.vsAverage")
            ),
            severity: severity,
            category: .cashFlow,
            detailData: .periodTrend(periodPoints)
        ))

        // 2. Period records (merged best + worst — audit 2026-07: two retrospective
        // "trivia" cards collapsed into one neutral card; the detail view renders
        // both the best-10 and worst-10 rankings)
        if let best = periodPoints.max(by: { $0.netFlow < $1.netFlow }) {
            insights.append(Insight(
                id: "period_records",
                type: .bestMonth,
                title: String(localized: "insights.periodRecords"),
                subtitle: best.label,
                metric: InsightMetric(
                    value: best.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(best.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .neutral,
                category: .cashFlow,
                detailData: .periodTrend(periodPoints),
                // FULL history with min/max markers — for the records card the
                // extremes (and where they sit in time) ARE the message, so no
                // recent-tail slicing here.
                cardVisual: .sparkline(
                    points: periodPoints,
                    series: .cashFlow,
                    projectedValue: nil,
                    markExtremes: true
                )
            ))
        }

        // 4. Projected balance — recurring delta + average expenses scaled to granularity period.
        // Loans are liabilities — exclude from "current balance" so projections stay truthful.
        let currentBalance = snapshot.accounts.filter { !$0.isLoan && $0.includeInBalance }.reduce(0.0) { $0 + snapshot.balanceFor($1.id) }
        let recurringNet = monthlyRecurringNet(baseCurrency: baseCurrency, recurringSeries: snapshot.recurringSeries, categories: snapshot.categories)

        // Average monthly expenses from the last 3 period data points for a realistic projection.
        let avgMonthlyExpenses: Double = {
            let recentPoints = Array(periodPoints.suffix(3))
            guard !recentPoints.isEmpty else { return 0 }
            return recentPoints.reduce(0.0) { $0 + $1.expenses } / Double(recentPoints.count)
        }()

        let projectedPeriodMultiplier: Double
        let projectedPeriodUnit: String
        switch granularity {
        case .week:
            projectedPeriodMultiplier = 7.0 / 30.0
            projectedPeriodUnit       = String(localized: "insights.perWeek")
        case .quarter:
            projectedPeriodMultiplier = 3.0
            projectedPeriodUnit       = String(localized: "insights.perQuarter")
        case .year:
            projectedPeriodMultiplier = 12.0
            projectedPeriodUnit       = String(localized: "insights.perYear")
        case .month, .allTime:
            projectedPeriodMultiplier = 1.0
            projectedPeriodUnit       = String(localized: "insights.perMonth")
        }
        let periodRecurringNet    = recurringNet * projectedPeriodMultiplier
        let periodAvgExpenses     = avgMonthlyExpenses * projectedPeriodMultiplier
        let projectedNetChange    = periodRecurringNet - periodAvgExpenses
        let projectedBalance      = currentBalance + projectedNetChange
        let projectedMetricFormatted = projectedNetChange >= 0
            ? "+" + Formatting.formatCurrencySmart(projectedNetChange, currency: baseCurrency)
            : Formatting.formatCurrencySmart(projectedNetChange, currency: baseCurrency)

        let pbSeverity: InsightSeverity = projectedBalance >= 0 ? .positive : .critical
        let pbRecommendation: String
        if projectedNetChange >= 0 {
            pbRecommendation = String(localized: "insights.formula.projectedBalance.rec.growing")
        } else {
            let drop = -projectedNetChange
            pbRecommendation = String(
                format: String(localized: "insights.formula.projectedBalance.rec.dropping"),
                Formatting.formatCurrencySmart(drop, currency: baseCurrency)
            )
        }

        let pbModel = InsightFormulaModel(
            id: "projectedBalance",
            titleKey: "insights.formula.projectedBalance.title",
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            color: pbSeverity.color,
            heroValueText: Formatting.formatCurrencySmart(projectedBalance, currency: baseCurrency),
            heroLabelKey: "insights.formula.projectedBalance.heroLabel",
            formulaHeaderKey: "insights.formula.projectedBalance.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "currentBalance", labelKey: "insights.formula.projectedBalance.row.currentBalance", value: currentBalance, kind: .currency),
                InsightFormulaRow(id: "recurringNet", labelKey: "insights.formula.projectedBalance.row.recurringNet", value: periodRecurringNet, kind: .currency),
                InsightFormulaRow(id: "avgExpenses", labelKey: "insights.formula.projectedBalance.row.avgExpenses", value: periodAvgExpenses, kind: .currency),
                InsightFormulaRow(id: "horizon", labelKey: "insights.formula.projectedBalance.row.horizon", value: projectedPeriodMultiplier, kind: .rawText(granularity.displayName)),
                InsightFormulaRow(id: "projected", labelKey: "insights.formula.projectedBalance.row.projected", value: projectedBalance, kind: .currency, isEmphasised: true)
            ],
            explainerKey: "insights.formula.projectedBalance.explainer",
            recommendation: pbRecommendation,
            baseCurrency: baseCurrency
        )

        insights.append(Insight(
            id: "projected_balance",
            type: .projectedBalance,
            title: String(localized: "insights.projectedBalance"),
            subtitle: String(localized: "insights.recurringAndExpenses"),
            metric: InsightMetric(
                value: projectedNetChange,
                formattedValue: projectedMetricFormatted,
                currency: baseCurrency,
                unit: projectedPeriodUnit
            ),
            trend: InsightTrend(
                direction: projectedNetChange >= 0 ? .up : .down,
                changePercent: currentBalance > 0 ? (projectedNetChange / currentBalance) * 100 : nil,
                changeAbsolute: projectedNetChange,
                comparisonPeriod: String(localized: "insights.currentBalance") + ": "
                    + Formatting.formatCurrencySmart(currentBalance, currency: baseCurrency)
            ),
            severity: pbSeverity,
            category: .cashFlow,
            detailData: .formulaBreakdown(pbModel),
            // Balance trajectory (cumulative, recent 12 periods) with a dashed
            // projection tail to the projected balance — forecast grammar.
            cardVisual: {
                let initialBalance = currentBalance - periodPoints.reduce(0.0) { $0 + $1.netFlow }
                var running = initialBalance
                let balancePoints: [PeriodDataPoint] = periodPoints.map { p in
                    running += p.netFlow
                    return PeriodDataPoint(
                        id: p.id, granularity: p.granularity, key: p.key,
                        periodStart: p.periodStart, periodEnd: p.periodEnd, label: p.label,
                        income: p.income, expenses: p.expenses, cumulativeBalance: running
                    )
                }
                let recent = Array(balancePoints.suffix(12))
                guard recent.count >= 2 else { return nil }
                return .sparkline(
                    points: recent,
                    series: .wealth,
                    projectedValue: projectedBalance,
                    markExtremes: false
                )
            }()
        ))

        return insights
    }
}
