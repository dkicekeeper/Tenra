//
//  InsightsService+Spending.swift
//  Tenra
//
//  Top spending category, period-over-period spending change,
//  average daily spending, spending spike detection, category trend.
//

import Foundation
import os
import SwiftUI

extension InsightsService {

    // MARK: - MoM Reference Date Helper

    /// Returns the reference date for month-over-month comparisons.
    /// For current/rolling filters (e.g. "This Month", "Last 30 Days") this is today,
    /// so "this month" = the current calendar month.
    /// For historical filters (e.g. "Last Year", "Last 3 Months") this is the filter's
    /// INCLUSIVE last day (end - 1 second), because `timeFilter.dateRange().end` is
    /// EXCLUSIVE (e.g. "Last Month" Jan 2026 → end = Feb 1 2026 00:00:00).
    nonisolated func momReferenceDate(for timeFilter: TimeFilter) -> Date {
        let end = timeFilter.dateRange().end
        if Calendar.current.isDateInToday(end) || end > Date() {
            return Date()
        }
        return Calendar.current.date(byAdding: .second, value: -1, to: end) ?? end
    }

    // MARK: - Spending Insights

    nonisolated func generateSpendingInsights(
        filtered: [Transaction],
        allTransactions: [Transaction],
        periodSummary: PeriodSummary,
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        granularity: InsightGranularity? = nil,
        periodPoints: [PeriodDataPoint] = [],
        txDateMap: [String: Date]? = nil,
        preAggregated: PreAggregatedData? = nil,
        categories: [CustomCategory]
    ) -> [Insight] {
        var insights: [Insight] = []
        let expenses = filterService.filterByType(filtered, type: .expense)
        guard !expenses.isEmpty else {
            Self.logger.debug("🛒 [Insights] Spending — SKIPPED (no expenses in period)")
            return insights
        }

        // 1. Top spending category
        // Narrow to the current granularity bucket when available so the breakdown
        // reflects only the current week / month / quarter / year — not the full window.
        let currentBucketPoint = granularity.flatMap { gran in
            periodPoints.first(where: { $0.key == gran.currentPeriodKey })
        }

        let topExpenses: [Transaction]
        let topTotalExpenses: Double

        if let cp = currentBucketPoint {
            _ = (cp.periodStart, cp.periodEnd) // topRange was unused
            // Use dateMap for O(1) date lookups — avoids O(N) DateFormatter re-parsing
            if let map = txDateMap {
                topExpenses = expenses.filter { tx in
                    guard let d = map[tx.date], d >= cp.periodStart, d < cp.periodEnd else { return false }
                    return true
                }
            } else {
                topExpenses = filterService.filterByTimeRange(expenses, start: cp.periodStart, end: cp.periodEnd)
            }
            topTotalExpenses = cp.expenses
        } else {
            _ = timeFilter.dateRange() // topRange was unused
            topExpenses = expenses
            topTotalExpenses = periodSummary.totalExpenses
        }

        // For .allTime with PreAggregatedData, use O(1) categoryTotals lookup.
        // For other granularities (or when preAggregated is nil), use the existing O(N) grouping.
        let sortedCategories: [(key: String, total: Double)]
        let categoryGroups: [String: [Transaction]]

        if granularity == .allTime, let catTotals = preAggregated?.categoryTotals, !catTotals.isEmpty {
            // O(1) path: dictionary already built in PreAggregatedData.build() single O(N) pass
            sortedCategories = catTotals
                .filter { !$0.key.isEmpty }
                .map { (key: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }
            // categoryGroups needed only for subcategory breakdown — build lazily only if needed
            categoryGroups = Dictionary(grouping: topExpenses, by: { $0.category })
        } else {
            // Original O(N) path for non-allTime granularities
            categoryGroups = Dictionary(grouping: topExpenses, by: { $0.category })
            sortedCategories = categoryGroups
                .map { key, txns in
                    let total = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                    return (key: key, total: total)
                }
                .sorted { $0.total > $1.total }
        }

        let topCategoryName = sortedCategories.first?.key ?? "—"
        let topCategoryAmount = sortedCategories.first?.total ?? 0
        Self.logger.debug("🛒 [Insights] Spending — bucket_expenses=\(topExpenses.count), categories=\(sortedCategories.count), top='\(topCategoryName, privacy: .public)' (\(String(format: "%.0f", topCategoryAmount), privacy: .public) \(baseCurrency, privacy: .public))")
        for cat in sortedCategories.prefix(5) {
            let pct = topTotalExpenses > 0 ? (cat.total / topTotalExpenses) * 100 : 0
            Self.logger.debug("   🛒 \(cat.key, privacy: .public): \(String(format: "%.0f", cat.total), privacy: .public) (\(String(format: "%.1f%%", pct), privacy: .public))")
        }

        if let top = sortedCategories.first {
            let percentage = topTotalExpenses > 0
                ? (top.total / topTotalExpenses) * 100
                : 0

            // Index categories by name once — replaces O(M²) scan (sortedCategories × categories)
            // with O(M) build + O(1) lookup per breakdown item.
            var categoryByName: [String: CustomCategory] = [:]
            categoryByName.reserveCapacity(categories.count)
            for cat in categories {
                categoryByName[cat.name] = cat
            }

            // Show ALL categories in breakdown
            let breakdownItems: [CategoryBreakdownItem] = sortedCategories.map { item in
                let pct = topTotalExpenses > 0 ? (item.total / topTotalExpenses) * 100 : 0
                let cat = categoryByName[item.key]
                let catColor = cat.map { Color(hex: $0.colorHex) } ?? AppColors.accent
                let txns = categoryGroups[item.key] ?? []

                let subcategoryTotals = Dictionary(grouping: txns, by: { $0.subcategory ?? "" })
                    .compactMap { subKey, subTxns -> SubcategoryBreakdownItem? in
                        guard !subKey.isEmpty else { return nil }
                        let subTotal = subTxns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                        return SubcategoryBreakdownItem(
                            id: subKey,
                            name: subKey,
                            amount: subTotal,
                            percentage: item.total > 0 ? (subTotal / item.total) * 100 : 0
                        )
                    }
                    .sorted { $0.amount > $1.amount }

                return CategoryBreakdownItem(
                    id: item.key,
                    categoryName: item.key,
                    amount: item.total,
                    percentage: pct,
                    color: catColor,
                    iconSource: cat?.iconSource,
                    subcategories: subcategoryTotals
                )
            }

            insights.append(Insight(
                id: "top_spending_\(top.key)",
                type: .topSpendingCategory,
                title: String(localized: "insights.topCategory"),
                subtitle: top.key,
                metric: InsightMetric(
                    value: top.total,
                    formattedValue: Formatting.formatCurrencySmart(top.total, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: .down,
                    changePercent: percentage,
                    changeAbsolute: nil,
                    comparisonPeriod: String(format: "%.0f%% %@", percentage, String(localized: "insights.ofTotal"))
                ),
                severity: percentage > 50 ? .warning : .neutral,
                category: .spending,
                detailData: .categoryBreakdown(breakdownItems)
            ))
        }

        // 2. Period-over-period spending change.
        // Use granularity bucket lookup when periodPoints available; fall back to legacy scan.
        // Skip for .allTime — there is no meaningful "previous all-time period".
        if let gran = granularity, !periodPoints.isEmpty, gran != .allTime {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let thisTotal    = currentPoint?.expenses ?? 0
            let prevTotal    = prevPoint?.expenses ?? 0

            Self.logger.debug("🔄 [Insights] MoP spending (granularity) — this=\(String(format: "%.0f", thisTotal), privacy: .public), prev=\(String(format: "%.0f", prevTotal), privacy: .public)")

            if let prevPoint, prevTotal > 0 {
                let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                let severity: InsightSeverity = changePercent > 20 ? .warning : (changePercent < -10 ? .positive : .neutral)

                insights.append(Insight(
                    id: "mom_spending",
                    type: .monthOverMonthChange,
                    title: gran.monthOverMonthTitle,
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
                    category: .spending,
                    detailData: .periodTrend([prevPoint, currentPoint].compactMap { $0 })
                ))
            }
        } else {
            // Legacy path: calendar-month O(N) scan (used when called from old timeFilter API).
            let calendar = Calendar.current
            let refDate = momReferenceDate(for: timeFilter)
            let thisMonthStart = startOfMonth(calendar, for: refDate)
            let fullMonthEnd = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) ?? refDate
            let refDatePlusOneDay = calendar.date(byAdding: .day, value: 1, to: refDate) ?? fullMonthEnd
            let thisMonthEnd = min(fullMonthEnd, refDatePlusOneDay)

            if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
               let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) {
                var thisMonthTotal: Double = 0
                var prevMonthTotal: Double = 0
                // Use txDateMap fast path when available — eliminates DateFormatter parse
                // (~16μs/tx × 19k = ~300ms saved per legacy MoM call).
                if let map = txDateMap {
                    for tx in allTransactions where tx.type == .expense {
                        guard let txDate = map[tx.date] else { continue }
                        let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                        if txDate >= thisMonthStart && txDate < thisMonthEnd { thisMonthTotal += amount }
                        else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevMonthTotal += amount }
                    }
                } else {
                    let dateFormatter = DateFormatters.dateFormatter
                    for tx in allTransactions where tx.type == .expense {
                        guard let txDate = dateFormatter.date(from: tx.date) else { continue }
                        let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                        if txDate >= thisMonthStart && txDate < thisMonthEnd { thisMonthTotal += amount }
                        else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevMonthTotal += amount }
                    }
                }
                if prevMonthTotal > 0 {
                    let changePercent = ((thisMonthTotal - prevMonthTotal) / prevMonthTotal) * 100
                    let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                    let severity: InsightSeverity = changePercent > 20 ? .warning : (changePercent < -10 ? .positive : .neutral)
                    insights.append(Insight(
                        id: "mom_spending",
                        type: .monthOverMonthChange,
                        title: String(localized: "insights.monthOverMonth"),
                        subtitle: String(localized: "insights.vsPreviousPeriod"),
                        metric: InsightMetric(
                            value: thisMonthTotal,
                            formattedValue: Formatting.formatCurrencySmart(thisMonthTotal, currency: baseCurrency),
                            currency: baseCurrency, unit: nil
                        ),
                        trend: InsightTrend(
                            direction: direction, changePercent: changePercent,
                            changeAbsolute: thisMonthTotal - prevMonthTotal,
                            comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
                        ),
                        severity: severity, category: .spending, detailData: nil
                    ))
                }
            }
        }

        // 3. Average daily spending.
        // Compute from current/previous granularity bucket when available.
        if let gran = granularity, !periodPoints.isEmpty {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let cal = Calendar.current
            let currentDays = currentPoint.map { max(1, cal.dateComponents([.day], from: $0.periodStart, to: $0.periodEnd).day ?? 1) } ?? 1
            let prevDays    = prevPoint.map    { max(1, cal.dateComponents([.day], from: $0.periodStart, to: $0.periodEnd).day ?? 1) } ?? 1
            let currentAvgDaily = (currentPoint?.expenses ?? 0) / Double(currentDays)
            let prevAvgDaily    = (prevPoint?.expenses ?? 0)    / Double(prevDays)
            let changePercent   = prevAvgDaily > 0 ? ((currentAvgDaily - prevAvgDaily) / prevAvgDaily) * 100 : 0.0
            let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)

            Self.logger.debug("📆 [Insights] Avg daily (granularity) — current=\(String(format: "%.0f", currentAvgDaily), privacy: .public), prev=\(String(format: "%.0f", prevAvgDaily), privacy: .public), change=\(String(format: "%+.1f%%", changePercent), privacy: .public)")

            insights.append(Insight(
                id: "avg_daily",
                type: .averageDailySpending,
                title: String(localized: "insights.avgDailySpending"),
                subtitle: currentPoint?.label ?? "",
                metric: InsightMetric(
                    value: currentAvgDaily,
                    formattedValue: Formatting.formatCurrencySmart(currentAvgDaily, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: prevAvgDaily > 0 ? InsightTrend(
                    direction: direction,
                    changePercent: changePercent,
                    changeAbsolute: currentAvgDaily - prevAvgDaily,
                    comparisonPeriod: gran.comparisonPeriodName
                ) : nil,
                severity: .neutral,
                category: .spending,
                detailData: .periodTrend([prevPoint, currentPoint].compactMap { $0 })
            ))
        } else {
            let calendar = Calendar.current
            let refDate = momReferenceDate(for: timeFilter)
            let periodRange = timeFilter.dateRange()
            let days = max(1, calendar.dateComponents([.day], from: periodRange.start, to: min(periodRange.end, refDate)).day ?? 1)
            let avgDaily = periodSummary.totalExpenses / Double(days)

            Self.logger.debug("📆 [Insights] Avg daily — totalExpenses=\(String(format: "%.0f", periodSummary.totalExpenses), privacy: .public), days=\(days), avg=\(String(format: "%.0f", avgDaily), privacy: .public) \(baseCurrency, privacy: .public)")

            insights.append(Insight(
                id: "avg_daily",
                type: .averageDailySpending,
                title: String(localized: "insights.avgDailySpending"),
                subtitle: "\(days) " + String(localized: "insights.days"),
                metric: InsightMetric(
                    value: avgDaily,
                    formattedValue: Formatting.formatCurrencySmart(avgDaily, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .neutral,
                category: .spending,
                detailData: nil
            ))
        }

        return insights
    }

    // MARK: - Spending Spike

    /// Detects a category whose current-month spending exceeds 1.5× its 3-month historical average.
    nonisolated func generateSpendingSpike(baseCurrency: String, transactions: [Transaction], preAggregated: PreAggregatedData? = nil) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: startOfMonth(calendar, for: now)) else { return nil }

        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let monthlyAggregates: [InMemoryCategoryMonthTotal]
        if let preAggregated {
            monthlyAggregates = preAggregated.categoryMonthTotalsInRange(from: threeMonthsAgo, to: now)
        } else {
            monthlyAggregates = Self.computeCategoryMonthTotals(
                from: transactions, from: threeMonthsAgo, to: now, baseCurrency: baseCurrency
            )
        }
        guard !monthlyAggregates.isEmpty else { return nil }

        let currentComps = calendar.dateComponents([.year, .month], from: now)
        let currentYear = currentComps.year ?? 0
        let currentMonth = currentComps.month ?? 0

        let byCategory = Dictionary(grouping: monthlyAggregates, by: { $0.categoryName })

        let totalExpensesInWindow = monthlyAggregates.reduce(0.0) { $0 + $1.totalExpenses }

        var spikeCategory: String? = nil
        var spikeAmount: Double = 0
        var spikeMultiplier: Double = 1.5

        for (catName, records) in byCategory {
            let current = records.first { $0.year == currentYear && $0.month == currentMonth }
            let historical = records.filter { !($0.year == currentYear && $0.month == currentMonth) }
            guard let currentAmount = current?.totalExpenses, currentAmount > 0, !historical.isEmpty else { continue }

            let histAvg = historical.reduce(0.0) { $0 + $1.totalExpenses } / Double(historical.count)
            guard totalExpensesInWindow > 0, histAvg / totalExpensesInWindow > 0.01 else { continue }

            let multiplier = currentAmount / histAvg
            if multiplier > spikeMultiplier {
                spikeMultiplier = multiplier
                spikeCategory = catName
                spikeAmount = currentAmount
            }
        }

        guard let catName = spikeCategory else { return nil }
        let changePercent = (spikeMultiplier - 1) * 100

        Self.logger.debug("⚡️ [Insights] SpendingSpike — '\(catName, privacy: .public)' ×\(String(format: "%.1f", spikeMultiplier), privacy: .public)")
        return Insight(
            id: "spending_spike",
            type: .spendingSpike,
            title: String(localized: "insights.spendingSpike"),
            subtitle: catName,
            metric: InsightMetric(
                value: spikeAmount,
                formattedValue: Formatting.formatCurrencySmart(spikeAmount, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: .up,
                changePercent: changePercent,
                changeAbsolute: nil,
                comparisonPeriod: String(localized: "insights.vsAverage")
            ),
            severity: spikeMultiplier > 2 ? .critical : .warning,
            category: .spending,
            detailData: nil
        )
    }

    // MARK: - Category Trend

    /// Finds the expense category that has been rising for the most consecutive months (min 2).
    nonisolated func generateCategoryTrend(baseCurrency: String, granularity: InsightGranularity, transactions: [Transaction], preAggregated: PreAggregatedData? = nil) -> Insight? {
        // Lookback window scales with granularity. Internal resolution stays monthly
        // (streak detection at month grain is the most useful signal); granularity
        // only changes how far back we look.
        let lookbackMonths: Int
        switch granularity {
        case .week:    lookbackMonths = 3
        case .month:   lookbackMonths = 6
        case .quarter: lookbackMonths = 12
        case .year:    lookbackMonths = 24
        case .allTime: lookbackMonths = 12
        }

        let calendar = Calendar.current
        let now = Date()
        guard let lookbackStart = calendar.date(byAdding: .month, value: -lookbackMonths, to: startOfMonth(calendar, for: now)) else { return nil }

        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let monthlyAggregates: [InMemoryCategoryMonthTotal]
        if let preAggregated {
            monthlyAggregates = preAggregated.categoryMonthTotalsInRange(from: lookbackStart, to: now)
        } else {
            monthlyAggregates = Self.computeCategoryMonthTotals(
                from: transactions, from: lookbackStart, to: now, baseCurrency: baseCurrency
            )
        }
        guard monthlyAggregates.count >= 4 else { return nil }

        let byCategory = Dictionary(grouping: monthlyAggregates, by: { $0.categoryName })

        var bestCategory: String? = nil
        var bestStreak = 1
        var bestLatestAmount: Double = 0
        var bestChangePercent: Double = 0
        var bestSorted: [InMemoryCategoryMonthTotal] = []

        for (catName, records) in byCategory {
            guard records.count >= 3 else { continue }
            let sorted = records.sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }

            var streak = 0
            for i in (1..<sorted.count).reversed() {
                if sorted[i].totalExpenses > sorted[i - 1].totalExpenses {
                    streak += 1
                } else {
                    break
                }
            }
            if streak >= 3 && streak > bestStreak {
                bestStreak = streak
                bestCategory = catName
                bestLatestAmount = sorted.last?.totalExpenses ?? 0
                let prevAmount = sorted[max(0, sorted.count - 2)].totalExpenses
                bestChangePercent = prevAmount > 0 ? ((bestLatestAmount - prevAmount) / prevAmount) * 100 : 0
                bestSorted = sorted
            }
        }

        guard let catName = bestCategory else { return nil }

        // Build per-month rows for the formula breakdown — last 6 records max so the
        // card stays scannable.
        let displayRecords = Array(bestSorted.suffix(6))
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        var formulaRows: [InsightFormulaRow] = displayRecords.map { rec in
            var comps = DateComponents(); comps.year = rec.year; comps.month = rec.month; comps.day = 1
            let date = calendar.date(from: comps) ?? Date()
            let label = monthFormatter.string(from: date)
            return InsightFormulaRow(
                id: "\(rec.year)-\(rec.month)",
                labelKey: "insights.formula.categoryTrend.row.month",
                value: rec.totalExpenses,
                kind: .rawText("\(label) — \(Formatting.formatCurrencySmart(rec.totalExpenses, currency: baseCurrency))")
            )
        }
        formulaRows.append(InsightFormulaRow(
            id: "delta",
            labelKey: "insights.formula.categoryTrend.row.delta",
            value: bestChangePercent,
            kind: .percent,
            isEmphasised: true
        ))

        let recommendation = String(
            format: String(localized: "insights.formula.categoryTrend.rec"),
            catName, bestStreak + 1
        )

        let model = InsightFormulaModel(
            id: "categoryTrend",
            titleKey: "insights.formula.categoryTrend.title",
            icon: "chart.line.uptrend.xyaxis",
            color: AppColors.warning,
            heroValueText: catName,
            heroLabelKey: "insights.formula.categoryTrend.heroLabel",
            formulaHeaderKey: "insights.formula.categoryTrend.formulaHeader",
            formulaRows: formulaRows,
            explainerKey: "insights.formula.categoryTrend.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("📈 [Insights] CategoryTrend — '\(catName, privacy: .public)' rising \(bestStreak + 1) months, lookback=\(lookbackMonths)mo")
        return Insight(
            id: "category_trend_\(catName)",
            type: .categoryTrend,
            title: String(localized: "insights.categoryTrend"),
            subtitle: String(format: String(localized: "insights.categoryTrend.risingMonths"), bestStreak + 1),
            metric: InsightMetric(
                value: bestLatestAmount,
                formattedValue: Formatting.formatCurrencySmart(bestLatestAmount, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: .up,
                changePercent: bestChangePercent,
                changeAbsolute: nil,
                comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
            ),
            severity: .warning,
            category: .spending,
            detailData: .formulaBreakdown(model)
        )
    }
}
