//
//  InsightsService+Forecasting.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: spending forecast, balance runway, year-over-year, income seasonality,
//                   spending velocity, income source breakdown.
//

import CoreData
import Foundation
import os
import SwiftUI

extension InsightsService {

    // MARK: - Forecasting Insights (Phase 24)

    func generateForecastingInsights(
        allTransactions: [Transaction],
        baseCurrency: String,
        balanceFor: (String) -> Double,
        filteredTransactions: [Transaction]? = nil
    ) -> [Insight] {
        var insights: [Insight] = []

        if let forecast = generateSpendingForecast(baseCurrency: baseCurrency) {
            insights.append(forecast)
        }
        if let runway = generateBalanceRunway(baseCurrency: baseCurrency, balanceFor: balanceFor) {
            insights.append(runway)
        }
        if let yoy = generateYearOverYear(baseCurrency: baseCurrency) {
            insights.append(yoy)
        }
        if let seasonality = generateIncomeSeasonality(baseCurrency: baseCurrency) {
            insights.append(seasonality)
        }
        if let velocity = generateSpendingVelocity(baseCurrency: baseCurrency) {
            insights.append(velocity)
        }
        // Phase 30: use filteredTransactions (windowed) when available so incomeSourceBreakdown
        // respects the selected granularity period.
        let sourceTransactions = filteredTransactions ?? allTransactions
        if let breakdown = generateIncomeSourceBreakdown(allTransactions: sourceTransactions, baseCurrency: baseCurrency) {
            insights.append(breakdown)
        }
        return insights
    }

    // MARK: - Private Forecasting Sub-Generators

    /// Projects month-end spend = avg daily rate × remaining days + pending recurring.
    @MainActor
    private func generateSpendingForecast(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        let df = DateFormatters.dateFormatter

        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }

        // Phase 40: Direct in-memory expense sum for last 30 days
        let last30Spent = transactionStore.transactions
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

        let monthlyRecurringExpenses = transactionStore.recurringSeries
            .filter { $0.isActive }
            .filter { series in
                let isExpense = transactionStore.categories.first { c in c.name == series.category }?.type != .income
                return isExpense
            }
            .reduce(0.0) { total, series in
                guard let startDate = df.date(from: series.startDate) else { return total }
                if startDate > now { return total }
                return total + seriesMonthlyEquivalent(series, baseCurrency: baseCurrency)
            }

        // Phase 40: Current month totals from in-memory transactions
        let currentMonthData = Self.computeLastMonthlyTotals(1, from: transactionStore.transactions, baseCurrency: baseCurrency).first
        let spentSoFar = currentMonthData?.totalExpenses ?? 0
        let monthlyIncome = currentMonthData?.totalIncome ?? 0

        let pendingRecurring = max(0, (monthlyRecurringExpenses / Double(totalDaysInMonth)) * Double(daysRemaining))
        let forecast = spentSoFar + (avgDailySpend * Double(daysRemaining)) + pendingRecurring

        let severity: InsightSeverity = monthlyIncome > 0 ? (forecast > monthlyIncome ? .warning : .positive) : .neutral

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
            detailData: nil
        )
    }

    /// How many months the current balance will last at the current net-burn rate.
    @MainActor
    private func generateBalanceRunway(baseCurrency: String, balanceFor: (String) -> Double) -> Insight? {
        let currentBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard currentBalance > 0 else { return nil }

        // Phase 40: In-memory 3-month average net flow
        let aggregates = Self.computeLastMonthlyTotals(3, from: transactionStore.transactions, baseCurrency: baseCurrency)
        guard !aggregates.isEmpty else { return nil }

        let avgMonthlyNetFlow = aggregates.reduce(0.0) { $0 + $1.netFlow } / Double(aggregates.count)

        if avgMonthlyNetFlow > 0 {
            return Insight(
                id: "balance_runway",
                type: .balanceRunway,
                title: String(localized: "insights.balanceRunway"),
                subtitle: Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency) + " " + String(localized: "insights.perMonth"),
                metric: InsightMetric(
                    value: avgMonthlyNetFlow,
                    formattedValue: "+" + Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: String(localized: "insights.perMonth")
                ),
                trend: nil,
                severity: .positive,
                category: .forecasting,
                detailData: nil
            )
        }

        let runway = currentBalance / abs(avgMonthlyNetFlow)
        let severity: InsightSeverity = runway >= 3 ? .positive : (runway >= 1 ? .warning : .critical)
        Self.logger.debug("🛤 [Insights] BalanceRunway — balance=\(String(format: "%.0f", currentBalance), privacy: .public), burn=\(String(format: "%.0f", avgMonthlyNetFlow), privacy: .public)/mo, runway=\(String(format: "%.1f", runway), privacy: .public) months")
        return Insight(
            id: "balance_runway",
            type: .balanceRunway,
            title: String(localized: "insights.balanceRunway"),
            subtitle: String(format: "%.1f " + String(localized: "insights.balanceRunway.months"), runway),
            metric: InsightMetric(
                value: runway,
                formattedValue: String(format: "%.1f", runway),
                currency: nil,
                unit: String(localized: "insights.months")
            ),
            trend: nil,
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Compares this month's expenses against the same month last year.
    @MainActor
    private func generateYearOverYear(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }

        // Phase 40: In-memory lookups replace MonthlyAggregateService.fetchLast()
        let thisMonth = Self.computeLastMonthlyTotals(1, from: transactionStore.transactions, baseCurrency: baseCurrency).first
        let lastYear = Self.computeLastMonthlyTotals(1, from: transactionStore.transactions, anchor: oneYearAgo, baseCurrency: baseCurrency).first

        guard let thisExpenses = thisMonth?.totalExpenses,
              let lastYearExpenses = lastYear?.totalExpenses,
              lastYearExpenses > 0 else { return nil }

        let delta = ((thisExpenses - lastYearExpenses) / lastYearExpenses) * 100
        guard abs(delta) > 3 else { return nil }

        let direction: TrendDirection = delta > 0 ? .up : .down
        let severity: InsightSeverity = delta <= -10 ? .positive : (delta >= 15 ? .warning : .neutral)
        let thisLabel = thisMonth?.label ?? ""
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
                changeAbsolute: thisExpenses - lastYearExpenses,
                comparisonPeriod: String(localized: "insights.yearOverYear")
            ),
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Identifies which calendar month historically generates the highest income.
    @MainActor
    private func generateIncomeSeasonality(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now) else { return nil }

        // Phase 40: In-memory computation replaces MonthlyAggregateService.fetchRange()
        let allAggregates = Self.computeMonthlyTotals(
            from: transactionStore.transactions, from: fiveYearsAgo, to: now, baseCurrency: baseCurrency
        )
        guard allAggregates.count >= 12 else { return nil }

        var incomeByMonth = [Int: [Double]]()
        for agg in allAggregates where agg.totalIncome > 0 {
            incomeByMonth[agg.month, default: []].append(agg.totalIncome)
        }
        guard incomeByMonth.count >= 6 else { return nil }

        let avgByMonth: [(month: Int, avg: Double)] = incomeByMonth.map { month, incomes in
            (month: month, avg: incomes.reduce(0, +) / Double(incomes.count))
        }
        let overallAvg = avgByMonth.reduce(0.0) { $0 + $1.avg } / Double(avgByMonth.count)
        guard overallAvg > 0 else { return nil }

        guard let peak = avgByMonth.max(by: { $0.avg < $1.avg }) else { return nil }
        let peakPercent = ((peak.avg - overallAvg) / overallAvg) * 100
        guard peakPercent > 10 else { return nil }

        let monthDate = calendar.date(from: DateComponents(year: 2024, month: peak.month, day: 1)) ?? now
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        monthFormatter.locale = .current
        let monthName = monthFormatter.string(from: monthDate)

        Self.logger.debug("🌊 [Insights] IncomeSeasonality — peak month \(peak.month) (\(monthName, privacy: .public)), +\(String(format: "%.0f%%", peakPercent), privacy: .public) above avg")
        return Insight(
            id: "income_seasonality",
            type: .incomeSeasonality,
            title: String(localized: "insights.incomeSeasonality"),
            subtitle: monthName,
            metric: InsightMetric(
                value: peakPercent,
                formattedValue: String(format: "+%.0f%%", peakPercent),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Compares current daily spending rate vs last month's daily rate.
    @MainActor
    private func generateSpendingVelocity(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        let dayOfMonth = calendar.component(.day, from: now)
        guard dayOfMonth > 3 else { return nil }

        // Phase 40: In-memory lookups replace MonthlyAggregateService.fetchLast()
        // fetchLast(1) → [currentMonth], .first = currentMonth
        // fetchLast(2) → [prevMonth, currentMonth], .first = prevMonth
        let thisMonth = Self.computeLastMonthlyTotals(1, from: transactionStore.transactions, baseCurrency: baseCurrency).first
        let lastMonth = Self.computeLastMonthlyTotals(2, from: transactionStore.transactions, baseCurrency: baseCurrency).first

        guard let spentSoFar = thisMonth?.totalExpenses, spentSoFar > 0 else { return nil }
        guard let lastMonthTotal = lastMonth?.totalExpenses, lastMonthTotal > 0 else { return nil }

        let currentDailyRate = spentSoFar / Double(dayOfMonth)

        guard let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let lastMonthDays = Double(calendar.range(of: .day, in: .month, for: prevMonthDate)?.count ?? 30)
        let lastMonthDailyRate = lastMonthTotal / lastMonthDays

        let ratio = currentDailyRate / lastMonthDailyRate
        guard abs(ratio - 1.0) > 0.1 else { return nil }

        let changePercent = (ratio - 1.0) * 100
        let direction: TrendDirection = ratio > 1 ? .up : .down
        let severity: InsightSeverity = ratio > 1.3 ? .warning : (ratio < 0.8 ? .positive : .neutral)

        Self.logger.debug("⏱ [Insights] SpendingVelocity — ratio=\(String(format: "%.2f", ratio), privacy: .public)x, change=\(String(format: "%+.1f%%", changePercent), privacy: .public)")
        return Insight(
            id: "spending_velocity",
            type: .spendingVelocity,
            title: String(localized: "insights.spendingVelocity"),
            subtitle: String(format: "%+.0f%%", changePercent),
            metric: InsightMetric(
                value: ratio,
                formattedValue: String(format: "%.1fx", ratio),
                currency: nil,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: changePercent,
                changeAbsolute: currentDailyRate - lastMonthDailyRate,
                comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
            ),
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    // MARK: - Income Source Breakdown

    /// Groups income transactions by category to show income source distribution.
    /// Phase 31: Uses CoreData fetch for full-history income totals by category.
    @MainActor
    func generateIncomeSourceBreakdown(allTransactions: [Transaction], baseCurrency: String) -> Insight? {
        let incomeCategories = transactionStore.categories.filter { $0.type == .income }
        guard incomeCategories.count >= 2 else { return nil }

        let cdIncomeByCategory = fetchIncomeByCategoryFromCoreData(baseCurrency: baseCurrency)

        let breakdownItems: [CategoryBreakdownItem]
        if !cdIncomeByCategory.isEmpty {
            let totalIncome = cdIncomeByCategory.values.reduce(0.0, +)
            guard totalIncome > 0 else { return nil }
            breakdownItems = cdIncomeByCategory
                .map { catName, amount -> CategoryBreakdownItem in
                    let pct = (amount / totalIncome) * 100
                    let cat = transactionStore.categories.first { $0.name == catName }
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
        } else {
            let incomeTransactions = allTransactions.filter { $0.type == .income }
            guard !incomeTransactions.isEmpty else { return nil }
            let totalIncome = incomeTransactions.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
            guard totalIncome > 0 else { return nil }
            let grouped = Dictionary(grouping: incomeTransactions, by: { $0.category })
            breakdownItems = grouped
                .map { catName, txns -> CategoryBreakdownItem in
                    let amount = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                    let pct = (amount / totalIncome) * 100
                    let cat = transactionStore.categories.first { $0.name == catName }
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
        }

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

    /// Phase 31: Fetch total income amounts grouped by category from full CoreData store.
    @MainActor
    private func fetchIncomeByCategoryFromCoreData(baseCurrency: String) -> [String: Double] {
        let context = CoreDataStack.shared.viewContext
        let request = NSFetchRequest<NSDictionary>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "type == %@ AND category != nil AND category != %@",
            "income", ""
        )
        request.propertiesToFetch = ["category", "amount", "convertedAmount", "currency"]
        request.resultType = .dictionaryResultType

        var result: [String: Double] = [:]
        do {
            let rows = try context.fetch(request) as! [[String: Any]]
            for row in rows {
                guard let catName = row["category"] as? String, !catName.isEmpty else { continue }
                let amount: Double
                if let currency = row["currency"] as? String, currency == baseCurrency,
                   let raw = row["amount"] as? Double {
                    amount = raw
                } else if let converted = row["convertedAmount"] as? Double, converted > 0 {
                    amount = converted
                } else if let raw = row["amount"] as? Double {
                    amount = raw
                } else {
                    continue
                }
                guard amount > 0 else { continue }
                result[catName, default: 0] += amount
            }
        } catch {
            Self.logger.error("❌ [Insights] fetchIncomeByCategoryFromCoreData failed: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }
}
