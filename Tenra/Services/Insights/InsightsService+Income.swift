//
//  InsightsService+Income.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: income growth (MoM / period-over-period), income vs expense ratio.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Income Insights

    nonisolated func generateIncomeInsights(
        filtered: [Transaction],
        allTransactions: [Transaction],
        periodSummary: PeriodSummary,
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        granularity: InsightGranularity? = nil,
        periodPoints: [PeriodDataPoint] = []
    ) -> [Insight] {
        var insights: [Insight] = []
        let incomeTransactions = filterService.filterByType(filtered, type: .income)
        guard !incomeTransactions.isEmpty else {
            Self.logger.debug("💵 [Insights] Income — SKIPPED (no income transactions in period)")
            return insights
        }

        Self.logger.debug("💵 [Insights] Income START — incomeTransactions=\(incomeTransactions.count)")

        // 1. Income growth (period-over-period).
        // Phase 30: use granularity bucket lookup when periodPoints available; fall back to legacy scan.
        // Skip .allTime — same reason as spending MoM: previousPeriodKey == currentPeriodKey → duplicate labels.
        if let gran = granularity, !periodPoints.isEmpty, gran != .allTime {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let thisTotal    = currentPoint?.income ?? 0
            let prevTotal    = prevPoint?.income ?? 0

            Self.logger.debug("💵 [Insights] Income growth (granularity) — this=\(String(format: "%.0f", thisTotal), privacy: .public), prev=\(String(format: "%.0f", prevTotal), privacy: .public)")

            if let prevPoint, prevTotal > 0 {
                let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                let severity: InsightSeverity = changePercent > 10 ? .positive : (changePercent < -10 ? .warning : .neutral)

                insights.append(Insight(
                    id: "income_growth",
                    type: .incomeGrowth,
                    title: String(localized: "insights.incomeGrowth"),
                    subtitle: gran.comparisonPeriodName,
                    metric: InsightMetric(
                        value: thisTotal,
                        formattedValue: Formatting.formatCurrencySmart(thisTotal, currency: baseCurrency),
                        currency: baseCurrency,
                        unit: nil
                    ),
                    trend: InsightTrend(
                        direction: direction,
                        changePercent: changePercent,
                        changeAbsolute: thisTotal - prevTotal,
                        comparisonPeriod: gran.comparisonPeriodName
                    ),
                    severity: severity,
                    category: .income,
                    detailData: .periodTrend([prevPoint, currentPoint].compactMap { $0 })
                ))
            }
        } else {
            // Legacy path: calendar-month O(N) scan.
            let calendar = Calendar.current
            let refDate = momReferenceDate(for: timeFilter)
            let thisMonthStart = startOfMonth(calendar, for: refDate)
            let fullMonthEnd = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) ?? refDate
            let refDatePlusOneDay = calendar.date(byAdding: .day, value: 1, to: refDate) ?? fullMonthEnd
            let thisMonthEnd = min(fullMonthEnd, refDatePlusOneDay)

            if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
               let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) {
                var thisTotal: Double = 0
                var prevTotal: Double = 0
                let dateFormatter = DateFormatters.dateFormatter
                for tx in allTransactions where tx.type == .income {
                    guard let txDate = dateFormatter.date(from: tx.date) else { continue }
                    let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                    if txDate >= thisMonthStart && txDate < thisMonthEnd { thisTotal += amount }
                    else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevTotal += amount }
                }
                if prevTotal > 0 {
                    let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                    let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                    let severity: InsightSeverity = changePercent > 10 ? .positive : (changePercent < -10 ? .warning : .neutral)
                    insights.append(Insight(
                        id: "income_growth", type: .incomeGrowth,
                        title: String(localized: "insights.incomeGrowth"),
                        subtitle: String(localized: "insights.vsPreviousPeriod"),
                        metric: InsightMetric(value: thisTotal,
                            formattedValue: Formatting.formatCurrencySmart(thisTotal, currency: baseCurrency),
                            currency: baseCurrency, unit: nil),
                        trend: InsightTrend(direction: direction, changePercent: changePercent,
                            changeAbsolute: thisTotal - prevTotal,
                            comparisonPeriod: String(localized: "insights.vsPreviousPeriod")),
                        severity: severity, category: .income, detailData: nil
                    ))
                }
            }
        }

        // 2. Income vs Expense ratio — reuse periodSummary (no extra calculateSummary call)
        if periodSummary.totalExpenses > 0 {
            let ratio = periodSummary.totalIncome / periodSummary.totalExpenses
            let severity: InsightSeverity = ratio >= 1.5 ? .positive : (ratio >= 1.0 ? .neutral : .critical)
            Self.logger.debug("💵 [Insights] I/E ratio=\(String(format: "%.2f", ratio), privacy: .public)x, severity=\(String(describing: severity), privacy: .public)")

            insights.append(Insight(
                id: "income_vs_expense",
                type: .incomeVsExpenseRatio,
                title: String(localized: "insights.incomeVsExpense"),
                subtitle: String(localized: "insights.ratio"),
                metric: InsightMetric(
                    value: ratio,
                    formattedValue: String(format: "%.1fx", ratio),
                    currency: nil,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: ratio >= 1.0 ? .up : .down,
                    changePercent: nil,
                    changeAbsolute: periodSummary.netFlow,
                    comparisonPeriod: Formatting.formatCurrencySmart(periodSummary.netFlow, currency: baseCurrency)
                ),
                severity: severity,
                category: .income,
                detailData: periodPoints.isEmpty ? nil : .periodTrend(periodPoints)
            ))
        }

        Self.logger.debug("💵 [Insights] Income END — \(insights.count) insights")
        return insights
    }
}
