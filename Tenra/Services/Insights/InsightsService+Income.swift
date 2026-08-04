//
//  InsightsService+Income.swift
//  Tenra
//
//  Income growth and trend insights.
//  Responsible for: income growth (MoM / period-over-period).
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
        periodPoints: [PeriodDataPoint] = [],
        txDateMap: [String: Date]? = nil
    ) -> [Insight] {
        var insights: [Insight] = []
        // Deposit interest accrual counts as income (canonical summaryContribution rule),
        // so this can't use filterService.filterByType(_:type:) — raw `.income` only.
        let incomeTransactions = filtered.filter { Self.moneyBucket($0.type) == .income }
        guard !incomeTransactions.isEmpty else {
            Self.logger.debug("💵 [Insights] Income — SKIPPED (no income transactions in period)")
            return insights
        }

        Self.logger.debug("💵 [Insights] Income START — incomeTransactions=\(incomeTransactions.count)")

        // 1. Income growth (period-over-period).
        // Use granularity bucket lookup when periodPoints available; fall back to legacy scan.
        // Skip .allTime — previousPeriodKey == currentPeriodKey → duplicate labels.
        if let gran = granularity, !periodPoints.isEmpty, gran != .allTime {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let thisTotal    = currentPoint?.income ?? 0
            let prevTotal    = prevPoint?.income ?? 0

            Self.logger.debug("💵 [Insights] Income growth (granularity) — this=\(String(format: "%.0f", thisTotal), privacy: .public), prev=\(String(format: "%.0f", prevTotal), privacy: .public)")

            if prevPoint != nil, prevTotal > 0 {
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
                    // Show the full granularity history (all periods), not just prev→current.
                    detailData: .periodTrend(periodPoints)
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
                // Use txDateMap fast path when available — eliminates DateFormatter parse
                // (~16μs/tx × 19k = ~300ms saved per legacy MoM income call).
                if let map = txDateMap {
                    for tx in allTransactions where Self.moneyBucket(tx.type) == .income {
                        guard let txDate = map[tx.date] else { continue }
                        let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                        if txDate >= thisMonthStart && txDate < thisMonthEnd { thisTotal += amount }
                        else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevTotal += amount }
                    }
                } else {
                    for tx in allTransactions where Self.moneyBucket(tx.type) == .income {
                        guard let txDate = FastDateParser.date(from: tx.date) else { continue }
                        let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                        if txDate >= thisMonthStart && txDate < thisMonthEnd { thisTotal += amount }
                        else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevTotal += amount }
                    }
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

        // NOTE (Insights product audit 2026-07): incomeVsExpenseRatio removed —
        // the "1.2x" multiplier duplicated savingsRate + netCashFlow with a less
        // intuitive formula. No benchmark app surfaces this as a standalone card.

        Self.logger.debug("💵 [Insights] Income END — \(insights.count) insights")
        return insights
    }
}
