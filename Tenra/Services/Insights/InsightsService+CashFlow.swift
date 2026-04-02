//
//  InsightsService+CashFlow.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: net cash flow trend, best/worst period, projected balance from recurring.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Cash Flow Insights (legacy timeFilter path)

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

        // 2. Best month
        if let best = periodData.max(by: { $0.netFlow < $1.netFlow }) {
            insights.append(Insight(
                id: "best_month",
                type: .bestMonth,
                title: String(localized: "insights.bestMonth"),
                subtitle: best.label,
                metric: InsightMetric(
                    value: best.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(best.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .positive,
                category: .cashFlow,
                detailData: .periodTrend(periodData)
            ))
        }

        // 3. Projected balance (30 days ahead) — show recurring impact delta
        let currentBalance = snapshot.accounts.reduce(0.0) { $0 + snapshot.balanceFor($1.id) }
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

    // MARK: - Cash Flow from Period Points (Phase 18)

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

        // 2. Best period
        let bestPeriod = periodPoints.max(by: { $0.netFlow < $1.netFlow })
        if let best = bestPeriod {
            insights.append(Insight(
                id: "best_month",
                type: .bestMonth,
                title: granularity.bestPeriodTitle,
                subtitle: best.label,
                metric: InsightMetric(
                    value: best.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(best.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .positive,
                category: .cashFlow,
                detailData: .periodTrend(periodPoints)
            ))
        }

        // 3. Worst period (Phase 24)
        if let worst = periodPoints.min(by: { $0.netFlow < $1.netFlow }),
           worst.netFlow < 0,
           worst.key != (bestPeriod?.key ?? "") {
            insights.append(Insight(
                id: "worst_month",
                type: .worstMonth,
                title: granularity.worstPeriodTitle,
                subtitle: worst.label,
                metric: InsightMetric(
                    value: worst.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(worst.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .warning,
                category: .cashFlow,
                detailData: .periodTrend(periodPoints)
            ))
        }

        // 4. Projected balance — recurring delta scaled to granularity period.
        let currentBalance = snapshot.accounts.reduce(0.0) { $0 + snapshot.balanceFor($1.id) }
        let recurringNet = monthlyRecurringNet(baseCurrency: baseCurrency, recurringSeries: snapshot.recurringSeries, categories: snapshot.categories)

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
        let periodRecurringNet  = recurringNet * projectedPeriodMultiplier
        let projectedBalance    = currentBalance + periodRecurringNet
        let projectedMetricFormatted = periodRecurringNet >= 0
            ? "+" + Formatting.formatCurrencySmart(periodRecurringNet, currency: baseCurrency)
            : Formatting.formatCurrencySmart(periodRecurringNet, currency: baseCurrency)

        insights.append(Insight(
            id: "projected_balance",
            type: .projectedBalance,
            title: String(localized: "insights.projectedBalance"),
            subtitle: projectedPeriodUnit,
            metric: InsightMetric(
                value: periodRecurringNet,
                formattedValue: projectedMetricFormatted,
                currency: baseCurrency,
                unit: projectedPeriodUnit
            ),
            trend: InsightTrend(
                direction: periodRecurringNet >= 0 ? .up : .down,
                changePercent: currentBalance > 0 ? (periodRecurringNet / currentBalance) * 100 : nil,
                changeAbsolute: periodRecurringNet,
                comparisonPeriod: String(localized: "insights.currentBalance") + ": "
                    + Formatting.formatCurrencySmart(currentBalance, currency: baseCurrency)
            ),
            severity: projectedBalance >= 0 ? .positive : .critical,
            category: .cashFlow,
            detailData: nil
        ))

        return insights
    }
}
