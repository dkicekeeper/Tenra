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

        // Realized-only filter: the breakdown must exclude future-dated (unrealized)
        // transactions, matching the period totals (cp.expenses) which already apply
        // LedgerPolicyRule.isRealized. Without this, a future-dated expense in the
        // current bucket inflated the top-spending breakdown vs. its own % total.
        let isRealizedTx: (Transaction) -> Bool = { tx in
            let d = txDateMap?[tx.date] ?? DateFormatters.dateFormatter.date(from: tx.date)
            return LedgerPolicyRule.isRealized(d)
        }

        // Index categories by name once — O(M) build + O(1) lookup per breakdown item.
        var categoryByName: [String: CustomCategory] = [:]
        categoryByName.reserveCapacity(categories.count)
        for cat in categories { categoryByName[cat.name] = cat }

        // Builds a sorted (desc) per-category breakdown for a set of expense txns.
        // `periodTotal` drives the percentage so it stays consistent with the period's
        // realized expense total (cp.expenses).
        let makeBreakdown: ([Transaction], Double) -> [CategoryBreakdownItem] = { txns, periodTotal in
            let groups = Dictionary(grouping: txns, by: { $0.category })
            return groups
                .map { key, catTxns -> (key: String, total: Double, txns: [Transaction]) in
                    let total = catTxns.reduce(0.0) { $0 + self.resolveAmount($1, baseCurrency: baseCurrency) }
                    return (key: key, total: total, txns: catTxns)
                }
                .filter { !$0.key.isEmpty }
                .sorted { $0.total > $1.total }
                .map { item in
                    let cat = categoryByName[item.key]
                    let catColor = cat.map { Color(hex: $0.colorHex) } ?? AppColors.accent
                    let subcategoryTotals = Dictionary(grouping: item.txns, by: { $0.subcategory ?? "" })
                        .compactMap { subKey, subTxns -> SubcategoryBreakdownItem? in
                            guard !subKey.isEmpty else { return nil }
                            let subTotal = subTxns.reduce(0.0) { $0 + self.resolveAmount($1, baseCurrency: baseCurrency) }
                            return SubcategoryBreakdownItem(
                                id: subKey, name: subKey, amount: subTotal,
                                percentage: item.total > 0 ? (subTotal / item.total) * 100 : 0
                            )
                        }
                        .sorted { $0.amount > $1.amount }
                    return CategoryBreakdownItem(
                        id: item.key,
                        categoryName: item.key,
                        amount: item.total,
                        percentage: periodTotal > 0 ? (item.total / periodTotal) * 100 : 0,
                        color: catColor,
                        iconSource: cat?.iconSource,
                        subcategories: subcategoryTotals
                    )
                }
        }

        // Paged path: for a finite granularity, build one breakdown per period so the
        // detail view can swipe across periods (current → back to the first tx). The
        // card stays present even when the current period has no expenses (empty state).
        if let gran = granularity, gran != .allTime, !periodPoints.isEmpty {
            // Bucket realized expenses by period key in a single pass.
            var expensesByKey: [String: [Transaction]] = [:]
            for tx in expenses {
                guard let d = (txDateMap?[tx.date] ?? DateFormatters.dateFormatter.date(from: tx.date)),
                      LedgerPolicyRule.isRealized(d) else { continue }
                expensesByKey[gran.groupingKey(for: d), default: []].append(tx)
            }

            let pages: [PeriodCategoryBreakdown] = periodPoints.map { pt in
                PeriodCategoryBreakdown(
                    id: pt.key,
                    label: gran.headingLabel(for: pt.key),
                    totalExpenses: pt.expenses,
                    items: makeBreakdown(expensesByKey[pt.key] ?? [], pt.expenses)
                )
            }

            let currentKey = gran.currentPeriodKey
            let currentIdx = periodPoints.firstIndex(where: { $0.key == currentKey }) ?? (periodPoints.count - 1)
            let currentPage = pages.indices.contains(currentIdx) ? pages[currentIdx] : pages.last
            let topItem = currentPage?.items.first

            let metric: InsightMetric
            let subtitle: String
            let trend: InsightTrend?
            let severity: InsightSeverity
            if let top = topItem {
                let pct = (currentPage?.totalExpenses ?? 0) > 0 ? (top.amount / currentPage!.totalExpenses) * 100 : 0
                metric = InsightMetric(
                    value: top.amount,
                    formattedValue: Formatting.formatCurrencySmart(top.amount, currency: baseCurrency),
                    currency: baseCurrency, unit: nil
                )
                subtitle = top.categoryName
                trend = InsightTrend(
                    direction: .down, changePercent: pct, changeAbsolute: nil,
                    comparisonPeriod: String(format: "%.0f%% %@", pct, String(localized: "insights.ofTotal"))
                )
                severity = pct > 50 ? .warning : .neutral
            } else {
                // Current period has no realized expenses — keep the card, show empty hero.
                metric = InsightMetric(
                    value: 0,
                    formattedValue: String(localized: "insights.noExpenses"),
                    currency: baseCurrency, unit: nil
                )
                subtitle = currentPage?.label ?? gran.headingLabel(for: currentKey)
                trend = nil
                severity = .neutral
            }

            Self.logger.debug("🛒 [Insights] Spending (paged) — periods=\(pages.count), currentIdx=\(currentIdx), currentTop='\(topItem?.categoryName ?? "—", privacy: .public)'")
            insights.append(Insight(
                id: "top_spending",
                type: .topSpendingCategory,
                title: String(localized: "insights.topCategory"),
                subtitle: subtitle,
                metric: metric,
                trend: trend,
                severity: severity,
                category: .spending,
                detailData: .categoryBreakdownPaged(CategoryBreakdownPages(periods: pages, currentIndex: currentIdx))
            ))
        } else {
            // Fallback / all-time path: a single non-paged breakdown for the current
            // bucket (or the whole window for .allTime).
            let topExpenses: [Transaction]
            let topTotalExpenses: Double

            if let cp = currentBucketPoint {
            _ = (cp.periodStart, cp.periodEnd) // topRange was unused
            // Use dateMap for O(1) date lookups — avoids O(N) DateFormatter re-parsing
            if let map = txDateMap {
                topExpenses = expenses.filter { tx in
                    guard let d = map[tx.date], d >= cp.periodStart, d < cp.periodEnd,
                          LedgerPolicyRule.isRealized(d) else { return false }
                    return true
                }
            } else {
                topExpenses = filterService.filterByTimeRange(expenses, start: cp.periodStart, end: cp.periodEnd)
                    .filter(isRealizedTx)
            }
            topTotalExpenses = cp.expenses
        } else if let gran = granularity, gran != .allTime {
            // No precomputed period point, but a finite granularity is selected — scope to
            // the current bucket's date range directly. Without this the top-category card
            // fell back to the full window below and showed all-time figures under e.g. month.
            let key = gran.currentPeriodKey
            let start = gran.periodStart(for: key)
            let end = gran.periodEnd(for: key)
            if let map = txDateMap {
                topExpenses = expenses.filter { tx in
                    guard let d = map[tx.date], d >= start, d < end,
                          LedgerPolicyRule.isRealized(d) else { return false }
                    return true
                }
            } else {
                topExpenses = filterService.filterByTimeRange(expenses, start: start, end: end)
                    .filter(isRealizedTx)
            }
            topTotalExpenses = topExpenses.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        } else {
            _ = timeFilter.dateRange() // topRange was unused
            topExpenses = expenses.filter(isRealizedTx)
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

            // Show ALL categories in breakdown (categoryByName indexed above)
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
                    // Show the full granularity history (all periods), not just prev→current.
                    detailData: .periodTrend(periodPoints),
                    // The card's message is a pairwise comparison — bar pair, not a sparkline.
                    cardVisual: .barPair(
                        previous: prevTotal,
                        current: thisTotal,
                        color: direction == .up ? AppColors.destructive
                             : direction == .down ? AppColors.success
                             : AppColors.accent,
                        isProjection: false
                    )
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
                        severity: severity, category: .spending, detailData: nil,
                        cardVisual: .barPair(
                            previous: prevMonthTotal,
                            current: thisMonthTotal,
                            color: direction == .up ? AppColors.destructive
                                 : direction == .down ? AppColors.success
                                 : AppColors.accent,
                            isProjection: false
                        )
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
                // Show the full granularity history (all periods), not just prev→current.
                detailData: .periodTrend(periodPoints)
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
            detailData: nil,
            // Gauge vs the category's own historical average (norm tick).
            cardVisual: .halfGauge(
                value: spikeAmount,
                norm: spikeAmount / spikeMultiplier,
                color: spikeMultiplier > 2 ? AppColors.destructive : AppColors.warning
            )
        )
    }

    // MARK: - Large Transaction (audit 2026-07)

    /// Copilot-style "big expense" detector: the largest non-recurring realized expense
    /// of the last 30 days, when it exceeds 4× the average expense transaction of the
    /// last 90 days. Recurring charges (rent, subscriptions) never fire it — the key
    /// predicate every benchmark app applies. Granularity-independent (shared).
    nonisolated func generateLargeTransaction(
        baseCurrency: String,
        transactions: [Transaction],
        txDateMap: [String: Date]? = nil
    ) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now),
              let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) else { return nil }
        let df = DateFormatters.dateFormatter

        // One pass: 90-day baseline (all realized expenses) + 30-day non-recurring candidate.
        var baselineTotal = 0.0
        var baselineCount = 0
        var candidate: (tx: Transaction, amountBase: Double, date: Date)?
        for tx in transactions where tx.type == .expense {
            guard let d = txDateMap?[tx.date] ?? df.date(from: tx.date),
                  d >= ninetyDaysAgo, d <= now else { continue }
            let amountBase = resolveAmount(tx, baseCurrency: baseCurrency)
            baselineTotal += amountBase
            baselineCount += 1
            if d >= thirtyDaysAgo, tx.recurringSeriesId == nil,
               amountBase > (candidate?.amountBase ?? 0) {
                candidate = (tx, amountBase, d)
            }
        }

        // A thin baseline makes the multiplier meaningless — require real history.
        guard baselineCount >= 20, let candidate else { return nil }
        let avgTx = baselineTotal / Double(baselineCount)
        guard avgTx > 0 else { return nil }
        let multiplier = candidate.amountBase / avgTx
        guard multiplier >= 4 else { return nil }

        let severity: InsightSeverity = multiplier >= 8 ? .warning : .neutral
        let dateLabel = DateFormatter.localizedString(from: candidate.date, dateStyle: .medium, timeStyle: .none)
        let name = candidate.tx.description.isEmpty ? candidate.tx.category : candidate.tx.description

        let model = InsightFormulaModel(
            id: "largeTransaction_\(candidate.tx.id)",
            titleKey: "insights.formula.largeTransaction.title",
            icon: "creditcard.trianglebadge.exclamationmark",
            color: severity.color,
            heroValueText: Formatting.formatCurrencySmart(candidate.amountBase, currency: baseCurrency),
            heroLabelKey: "insights.formula.largeTransaction.heroLabel",
            formulaHeaderKey: "insights.formula.largeTransaction.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "name", labelKey: "insights.formula.largeTransaction.row.name", value: 0, kind: .rawText(name)),
                InsightFormulaRow(id: "date", labelKey: "insights.formula.largeTransaction.row.date", value: 0, kind: .rawText(dateLabel)),
                InsightFormulaRow(id: "category", labelKey: "insights.formula.largeTransaction.row.category", value: 0, kind: .rawText(candidate.tx.category)),
                InsightFormulaRow(id: "amount", labelKey: "insights.formula.largeTransaction.row.amount", value: candidate.amountBase, kind: .currency),
                InsightFormulaRow(id: "avgTx", labelKey: "insights.formula.largeTransaction.row.avgTx", value: avgTx, kind: .currency),
                InsightFormulaRow(id: "multiplier", labelKey: "insights.formula.largeTransaction.row.multiplier", value: multiplier, kind: .rawText(String(format: "×%.1f", multiplier)), isEmphasised: true)
            ],
            explainerKey: "insights.formula.largeTransaction.explainer",
            recommendation: String(localized: "insights.formula.largeTransaction.rec"),
            baseCurrency: baseCurrency
        )

        Self.logger.debug("💳 [Insights] LargeTransaction — '\(name, privacy: .public)' \(String(format: "%.0f", candidate.amountBase), privacy: .public) \(baseCurrency, privacy: .public) = ×\(String(format: "%.1f", multiplier), privacy: .public) avg")
        return Insight(
            id: "large_tx_\(candidate.tx.id)",
            type: .largeTransaction,
            title: String(localized: "insights.largeTransaction"),
            subtitle: name + " — " + dateLabel,
            metric: InsightMetric(
                value: candidate.amountBase,
                formattedValue: Formatting.formatCurrencySmart(candidate.amountBase, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .spending,
            detailData: .formulaBreakdown(model),
            // Gauge vs the 90-day average bill — the norm tick pinned near the
            // start of an almost-full arc IS the "×14 the usual" story.
            cardVisual: .halfGauge(
                value: candidate.amountBase,
                norm: avgTx,
                color: multiplier >= 8 ? AppColors.destructive : AppColors.warning
            )
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
        // card stays scannable. Month name on the left (full + year), amount on the
        // right via the design-system currency formatter.
        let displayRecords = Array(bestSorted.suffix(6))
        var formulaRows: [InsightFormulaRow] = displayRecords.map { rec in
            var comps = DateComponents(); comps.year = rec.year; comps.month = rec.month; comps.day = 1
            let date = calendar.date(from: comps) ?? Date()
            let label = Self.monthYearFormatter.string(from: date)
            return InsightFormulaRow(
                id: "\(rec.year)-\(rec.month)",
                labelKey: "insights.formula.categoryTrend.row.month",
                labelText: label,
                value: rec.totalExpenses,
                kind: .currency
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
            detailData: .formulaBreakdown(model),
            // The category's own rising curve — built from the same month records
            // the formula rows show (streak ≥ 3 guarantees ≥ 4 points).
            cardVisual: .sparkline(
                points: displayRecords.map { rec in
                    var comps = DateComponents()
                    comps.year = rec.year; comps.month = rec.month; comps.day = 1
                    let start = calendar.date(from: comps) ?? Date()
                    let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                    let key = String(format: "%04d-%02d", rec.year, rec.month)
                    return PeriodDataPoint(
                        id: key, granularity: .month,
                        key: key,
                        // Real axis label — HeroSparkline plots these points on a
                        // category x-axis, where empty labels collapse into one
                        // duplicate category (MiniSparkline ignores labels).
                        periodStart: start, periodEnd: end,
                        label: InsightGranularity.month.periodLabel(for: key),
                        income: 0, expenses: rec.totalExpenses, cumulativeBalance: nil
                    )
                },
                series: .spending,
                projectedValue: nil,
                markExtremes: false
            )
        )
    }
}
