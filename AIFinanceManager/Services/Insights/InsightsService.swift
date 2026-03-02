//
//  InsightsService.swift
//  AIFinanceManager
//
//  Phase 38: Refactored from 2832 LOC monolith into domain-specific extension files.
//  This file retains: class declaration, init, public API, granularity API,
//  period data points, category deep dive, and shared helpers accessible to all extensions.
//
//  Domain generators live in:
//    InsightsService+Spending.swift   — momReferenceDate, generateSpendingInsights, generateSpendingSpike, generateCategoryTrend
//    InsightsService+Income.swift     — generateIncomeInsights
//    InsightsService+Budget.swift     — generateBudgetInsights
//    InsightsService+Recurring.swift  — generateRecurringInsights, generateSubscriptionGrowth, generateDuplicateSubscriptions
//    InsightsService+CashFlow.swift   — generateCashFlowInsights, generateCashFlowInsightsFromPeriodPoints
//    InsightsService+Wealth.swift     — generateWealthInsights, generateAccountDormancy
//    InsightsService+Savings.swift    — generateSavingsInsights
//    InsightsService+Forecasting.swift— generateForecastingInsights, generateIncomeSourceBreakdown
//    InsightsService+HealthScore.swift— computeHealthScore
//
//  Performance notes:
//  - Static DateFormatters avoid allocations inside loops
//  - calculateMonthlySummary bypasses global cacheManager cache (avoids cross-filter contamination)
//  - resolveAmount delegates to convertedAmount (already cached by TransactionCurrencyService)
//

import CoreData
import Foundation
import SwiftUI
import os

final class InsightsService: @unchecked Sendable {

    // MARK: - Logger
    // Internal so cross-file extensions can log with `Self.logger`.
    static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsService")

    // MARK: - Dependencies
    // Internal (no `private`) so cross-file extensions can access them directly.

    let transactionStore: TransactionStore
    let filterService: TransactionFilterService
    let queryService: TransactionQueryService
    let budgetService: CategoryBudgetService
    let cache: InsightsCache

    // MARK: - Static formatters (avoid per-call allocation)
    // Internal so cross-file extensions can use `Self.monthYearFormatter` etc.

    static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        f.locale = .current
        return f
    }()

    static let monthAbbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = .current
        return f
    }()

    static let yearMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    // MARK: - Init

    init(
        transactionStore: TransactionStore,
        filterService: TransactionFilterService,
        queryService: TransactionQueryService,
        budgetService: CategoryBudgetService,
        cache: InsightsCache
    ) {
        self.transactionStore = transactionStore
        self.filterService = filterService
        self.queryService = queryService
        self.budgetService = budgetService
        self.cache = cache
    }

    // MARK: - Public API

    @MainActor
    func generateAllInsights(
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        let cacheKey = InsightsCache.makeKey(timeFilter: timeFilter, baseCurrency: baseCurrency)
        if let cached = cache.get(key: cacheKey) {
            Self.logger.debug("⚡️ [Insights] Cache HIT — key=\(cacheKey, privacy: .public), count=\(cached.count)")
            return cached
        }

        let allTransactions = Array(transactionStore.transactions)
        let range = timeFilter.dateRange()
        let filtered = filterService.filterByTimeRange(allTransactions, start: range.start, end: range.end)

        Self.logger.debug("📊 [Insights] Generate START — filter=\(timeFilter.displayName, privacy: .public), currency=\(baseCurrency, privacy: .public), all=\(allTransactions.count), filtered=\(filtered.count)")

        // Single summary calculation for the filtered period — reused by spending + income sections.
        // IMPORTANT: We bypass queryService.calculateSummary here because it uses a global
        // TransactionCacheManager cache (cacheManager.cachedSummary) that is NOT invalidated
        // when the user switches time filters. This causes cross-filter contamination: switching
        // from "This Month" to "Last Month" would return February's partial data for the January
        // period summary. calculateMonthlySummary computes directly from the transaction slice.
        let (periodIncome, periodExpenses) = calculateMonthlySummary(
            transactions: filtered,
            baseCurrency: baseCurrency,
            currencyService: currencyService
        )
        let periodNetFlow = periodIncome - periodExpenses
        // Wrap into a local value type so downstream code keeps using .totalIncome / .totalExpenses syntax
        let periodSummary = PeriodSummary(totalIncome: periodIncome, totalExpenses: periodExpenses, netFlow: periodNetFlow)
        Self.logger.debug("💰 [Insights] Period summary — income=\(String(format: "%.0f", periodSummary.totalIncome), privacy: .public) \(baseCurrency, privacy: .public), expenses=\(String(format: "%.0f", periodSummary.totalExpenses), privacy: .public) \(baseCurrency, privacy: .public), net=\(String(format: "%.0f", periodSummary.netFlow), privacy: .public) \(baseCurrency, privacy: .public)")

        var insights: [Insight] = []

        insights.append(contentsOf: generateSpendingInsights(
            filtered: filtered,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        ))

        insights.append(contentsOf: generateIncomeInsights(
            filtered: filtered,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        ))

        insights.append(contentsOf: generateBudgetInsights(
            transactions: filtered,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency
        ))

        insights.append(contentsOf: generateRecurringInsights(baseCurrency: baseCurrency))

        insights.append(contentsOf: generateCashFlowInsights(
            allTransactions: allTransactions,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            balanceFor: balanceFor
        ))

        Self.logger.debug("✅ [Insights] Generate END — total insights=\(insights.count) (spending=\(insights.filter { $0.category == .spending }.count), income=\(insights.filter { $0.category == .income }.count), budget=\(insights.filter { $0.category == .budget }.count), recurring=\(insights.filter { $0.category == .recurring }.count), cashFlow=\(insights.filter { $0.category == .cashFlow }.count))")

        cache.set(key: cacheKey, insights: insights)
        return insights
    }

    func invalidateCache() {
        cache.invalidateAll()
    }

    // MARK: - Monthly Data Points (Phase 22: reads from MonthlyAggregateService)

    /// Compute monthly data points for chart display.
    ///
    /// Phase 22 optimization: reads pre-computed MonthlyAggregateEntity records from CoreData
    /// instead of scanning all transactions (O(M) lookups vs the previous O(N×M) passes).
    /// Falls back to the original transaction-scan path if aggregates are unavailable
    /// (e.g. on first launch before a full rebuild).
    @MainActor
    func computeMonthlyDataPoints(
        transactions: [Transaction],
        months: Int,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,  // kept for API compatibility; not used inside
        currencyService: TransactionCurrencyService,
        anchorDate: Date? = nil
    ) -> [MonthlyDataPoint] {

        let anchor = anchorDate ?? Date()

        // Phase 22: Try fast path — read from persistent MonthlyAggregateEntity
        let aggregates = transactionStore.monthlyAggregateService.fetchLast(
            months,
            anchor: anchor,
            currency: baseCurrency
        )

        // If we got a full set of aggregate records, use them directly (O(M) fetch)
        if aggregates.count == months {
            Self.logger.debug("⚡️ [Insights] Monthly points FAST PATH — \(months) months from CoreData aggregates")
            let dataPoints: [MonthlyDataPoint] = aggregates.map { agg in
                let monthDate = Calendar.current.date(
                    from: DateComponents(year: agg.year, month: agg.month, day: 1)
                ) ?? Date()
                return MonthlyDataPoint(
                    id: Self.yearMonthFormatter.string(from: monthDate),
                    month: monthDate,
                    income: agg.totalIncome,
                    expenses: agg.totalExpenses,
                    netFlow: agg.netFlow,
                    label: Self.monthYearFormatter.string(from: monthDate)
                )
            }
            Self.logger.debug("📅 [Insights] Monthly points END (fast) — \(dataPoints.count) points")
            return dataPoints
        }

        // Phase 22 fallback: aggregates not ready yet (first launch) — use transaction scan
        Self.logger.debug("📅 [Insights] Monthly points SLOW PATH — aggregates count=\(aggregates.count) (expected \(months)), scanning transactions")
        return computeMonthlyDataPointsSlow(
            transactions: transactions,
            months: months,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            anchor: anchor
        )
    }

    /// Original O(N×M) implementation used as fallback before aggregates are built.
    private func computeMonthlyDataPointsSlow(
        transactions: [Transaction],
        months: Int,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        anchor: Date
    ) -> [MonthlyDataPoint] {
        let calendar = Calendar.current
        var dataPoints: [MonthlyDataPoint] = []
        dataPoints.reserveCapacity(months)

        for i in (0..<months).reversed() {
            guard
                let monthStart = calendar.date(byAdding: .month, value: -i, to: startOfMonth(calendar, for: anchor)),
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            let monthTransactions = filterService.filterByTimeRange(transactions, start: monthStart, end: monthEnd)
            let (monthIncome, monthExpenses) = calculateMonthlySummary(
                transactions: monthTransactions,
                baseCurrency: baseCurrency,
                currencyService: currencyService
            )
            let monthNetFlow = monthIncome - monthExpenses
            let label = Self.monthYearFormatter.string(from: monthStart)

            dataPoints.append(MonthlyDataPoint(
                id: Self.yearMonthFormatter.string(from: monthStart),
                month: monthStart,
                income: monthIncome,
                expenses: monthExpenses,
                netFlow: monthNetFlow,
                label: label
            ))
        }

        return dataPoints
    }

    // MARK: - Category Deep Dive

    @MainActor
    func generateCategoryDeepDive(
        categoryName: String,
        allTransactions: [Transaction],
        timeFilter: TimeFilter,
        comparisonFilter: TimeFilter? = nil,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> (subcategories: [SubcategoryBreakdownItem], monthlyTrend: [MonthlyDataPoint], prevBucketTotal: Double) {
        // All category expense transactions (used for prev-bucket comparison)
        let allCategoryTransactions = allTransactions.filter { $0.category == categoryName && $0.type == .expense }

        // Period-scoped transactions for the subcategory breakdown (respects the selected filter)
        let range = timeFilter.dateRange()
        let periodCategoryTransactions = filterService.filterByTimeRange(allCategoryTransactions, start: range.start, end: range.end)

        let totalAmount = periodCategoryTransactions.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }

        // Subcategory breakdown — scoped to the selected time period
        let subcategories = Dictionary(grouping: periodCategoryTransactions, by: { $0.subcategory ?? String(localized: "insights.noSubcategory") })
            .map { key, txns -> SubcategoryBreakdownItem in
                let amount = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                return SubcategoryBreakdownItem(
                    id: key,
                    name: key,
                    amount: amount,
                    percentage: totalAmount > 0 ? (amount / totalAmount) * 100 : 0
                )
            }
            .sorted { $0.amount > $1.amount }

        // Previous-bucket total for period comparison card (Phase 31)
        var prevBucketTotal: Double = 0
        if let cf = comparisonFilter {
            let cfRange = cf.dateRange()
            prevBucketTotal = filterService
                .filterByTimeRange(allCategoryTransactions, start: cfRange.start, end: cfRange.end)
                .reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        }

        return (subcategories, [], prevBucketTotal)
    }

    // MARK: - Granularity-based API (Phase 18, updated Phase 23)

    /// Generates all insights for a given granularity.
    /// Phase 23: accepts pre-built `transactions` array — caller builds it once on MainActor,
    /// avoiding repeated Array(transactionStore.transactions) copies per granularity (P3/P4 fix).
    func generateAllInsights(
        granularity: InsightGranularity,
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        firstTransactionDate: Date? = nil          // hoisted by caller to avoid 5× O(N) re-scan
    ) -> (insights: [Insight], periodPoints: [PeriodDataPoint]) {
        // Determine the date window for this granularity.
        // For .week: last 52 weeks. For .month/.quarter/.year/.allTime: first tx → now (covers all).
        // Use the pre-computed value when provided; fall back to local scan if called standalone.
        let firstDate: Date?
        if let provided = firstTransactionDate {
            firstDate = provided
        } else {
            firstDate = allTransactions
                .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
                .min()
        }
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // Filter transactions to the granularity window so spending / income / budget / savings
        // all respect the selected period. For non-week granularities the window covers every
        // transaction, so this filter is a no-op and performance is unaffected.
        let windowedTransactions = filterService.filterByTimeRange(allTransactions, start: windowStart, end: windowEnd)

        // TimeFilter wrapping the window — passed to generators that use aggregate fetch ranges
        // and the MoM reference date helper.
        let granularityTimeFilter = TimeFilter(preset: .custom, startDate: windowStart, endDate: windowEnd)

        // Period summary scoped to the granularity window
        let (windowedIncome, windowedExpenses) = calculateMonthlySummary(
            transactions: windowedTransactions,
            baseCurrency: baseCurrency,
            currencyService: currencyService
        )
        let periodSummary = PeriodSummary(
            totalIncome: windowedIncome,
            totalExpenses: windowedExpenses,
            netFlow: windowedIncome - windowedExpenses
        )

        // Phase 30: Compute period data points BEFORE generators so spending/income can use
        // granularity-aware bucket comparisons (currentPeriodKey / previousPeriodKey) without
        // duplicate O(N) scans.
        let periodPoints = computePeriodDataPoints(
            transactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            firstTransactionDate: firstDate
        )

        var insights: [Insight] = []

        insights.append(contentsOf: generateSpendingInsights(
            filtered: windowedTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            granularity: granularity,
            periodPoints: periodPoints
        ))

        insights.append(contentsOf: generateIncomeInsights(
            filtered: windowedTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            granularity: granularity,
            periodPoints: periodPoints
        ))

        insights.append(contentsOf: generateBudgetInsights(
            transactions: windowedTransactions,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency
        ))

        insights.append(contentsOf: generateRecurringInsights(baseCurrency: baseCurrency, granularity: granularity))

        insights.append(contentsOf: generateCashFlowInsightsFromPeriodPoints(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor
        ))

        insights.append(contentsOf: generateWealthInsights(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            balanceFor: balanceFor
        ))

        // Phase 24 — Spending behavioral
        if let spike = generateSpendingSpike(baseCurrency: baseCurrency) {
            insights.append(spike)
        }
        if let trend = generateCategoryTrend(baseCurrency: baseCurrency) {
            insights.append(trend)
        }

        // Phase 24 — Recurring behavioral
        if let growth = generateSubscriptionGrowth(baseCurrency: baseCurrency) {
            insights.append(growth)
        }

        // Phase 24 — Savings category (uses windowed income/expenses to respect granularity)
        insights.append(contentsOf: generateSavingsInsights(
            allIncome: windowedIncome,
            allExpenses: windowedExpenses,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor
        ))

        // Phase 31: Narrow incomeSourceBreakdown to current granularity bucket only.
        // This ensures income sources reflect what was earned in the current period, not the full window.
        let currentBucketForForecasting: [Transaction]
        if let cp = periodPoints.first(where: { $0.key == granularity.currentPeriodKey }) {
            currentBucketForForecasting = filterService.filterByTimeRange(
                allTransactions, start: cp.periodStart, end: cp.periodEnd
            )
        } else {
            currentBucketForForecasting = windowedTransactions
        }

        // Phase 24 — Forecasting category
        insights.append(contentsOf: generateForecastingInsights(
            allTransactions: allTransactions,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor,
            filteredTransactions: currentBucketForForecasting
        ))

        // Phase 24 — Behavioral (appended to relevant existing categories)
        if let duplicates = generateDuplicateSubscriptions(baseCurrency: baseCurrency) {
            insights.append(duplicates)
        }
        if let dormancy = generateAccountDormancy(allTransactions: allTransactions, balanceFor: balanceFor) {
            insights.append(dormancy)
        }

        return (insights, periodPoints)
    }

    /// Computes a specific subset of granularities. Used by progressive loading in InsightsViewModel:
    /// Phase 1 computes the priority granularity for immediate display; Phase 2 computes the rest.
    func computeGranularities(
        _ granularities: [InsightGranularity],
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        firstTransactionDate: Date?
    ) -> [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])] {
        var results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])] = [:]
        for gran in granularities {
            results[gran] = generateAllInsights(
                granularity: gran,
                transactions: allTransactions,
                baseCurrency: baseCurrency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: balanceFor,
                firstTransactionDate: firstTransactionDate
            )
        }
        return results
    }

    /// Computes all insight granularities in a single @MainActor call.
    /// Called once from InsightsViewModel.loadInsightsBackground() to replace
    /// the 5-iteration for-loop that caused 5 separate main actor hops.
    func computeAllGranularities(
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        firstTransactionDate: Date?
    ) -> [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])] {
        return computeGranularities(
            InsightGranularity.allCases,
            transactions: allTransactions,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            balanceFor: balanceFor,
            firstTransactionDate: firstTransactionDate
        )
    }

    // MARK: - Period Data Points (Phase 18)

    /// Groups all transactions into PeriodDataPoint buckets according to granularity.
    func computePeriodDataPoints(
        transactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        firstTransactionDate: Date? = nil
    ) -> [PeriodDataPoint] {
        let dateFormatter = DateFormatters.dateFormatter
        let calendar = Calendar.current

        // Determine data window
        let firstDate = firstTransactionDate
            ?? transactions.compactMap { dateFormatter.date(from: $0.date) }.min()
            ?? Date()
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // Fast path for all non-week granularities — MonthlyAggregateService holds full history
        // regardless of the 3-month in-memory window (windowMonths = 3).
        // .month and .quarter were previously excluded, causing charts to show only 3 months.
        // .week spans 52 weeks at weekly resolution; monthly aggregates can't back-fill per-week
        // bars accurately, so it remains on the transaction-scan path (limited to window).
        switch granularity {
        case .year, .allTime, .month, .quarter:
            let monthlyAggs = transactionStore.monthlyAggregateService.fetchRange(
                from: windowStart, to: windowEnd, currency: baseCurrency
            )
            if !monthlyAggs.isEmpty {
                Self.logger.debug("⚡️ [Insights] PeriodDataPoints FAST PATH (\(granularity.rawValue)) — \(monthlyAggs.count) monthly records from CoreData")
                return computePeriodDataPointsFromAggregates(
                    monthlyAggs,
                    granularity: granularity,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    calendar: calendar
                )
            }
            // Fallback to transaction scan if aggregates not ready (first launch)
            guard !transactions.isEmpty else { return [] }
        case .week:
            guard !transactions.isEmpty else { return [] }
        }

        // Build ordered list of all keys in this window
        var orderedKeys: [String] = []
        var keySet = Set<String>()
        var cursor = windowStart
        while cursor < windowEnd {
            let key = granularity.groupingKey(for: cursor)
            if !keySet.contains(key) {
                orderedKeys.append(key)
                keySet.insert(key)
            }
            // Advance cursor by one unit
            switch granularity {
            case .week:    cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? windowEnd
            case .month:   cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? windowEnd
            case .quarter: cursor = calendar.date(byAdding: .month, value: 3, to: cursor) ?? windowEnd
            case .year:    cursor = calendar.date(byAdding: .year, value: 1, to: cursor) ?? windowEnd
            case .allTime: cursor = windowEnd
            }
        }

        // Aggregate transactions into buckets
        var incomeByKey = [String: Double]()
        var expensesByKey = [String: Double]()

        for tx in transactions {
            guard let txDate = dateFormatter.date(from: tx.date),
                  txDate >= windowStart, txDate < windowEnd else { continue }
            let key = granularity.groupingKey(for: txDate)
            let amount = currencyService.getConvertedAmountOrCompute(transaction: tx, to: baseCurrency)
            switch tx.type {
            case .income:  incomeByKey[key, default: 0] += amount
            case .expense: expensesByKey[key, default: 0] += amount
            default: break
            }
        }

        // Build result array in chronological order
        return orderedKeys.map { key in
            let periodStart = granularity.periodStart(for: key)
            let periodEnd: Date
            switch granularity {
            case .week:    periodEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: periodStart) ?? periodStart
            case .month:   periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart
            case .quarter: periodEnd = calendar.date(byAdding: .month, value: 3, to: periodStart) ?? periodStart
            case .year:    periodEnd = calendar.date(byAdding: .year, value: 1, to: periodStart) ?? periodStart
            case .allTime: periodEnd = windowEnd
            }
            return PeriodDataPoint(
                id: key,
                granularity: granularity,
                key: key,
                periodStart: periodStart,
                periodEnd: periodEnd,
                label: granularity.periodLabel(for: key),
                income: incomeByKey[key] ?? 0,
                expenses: expensesByKey[key] ?? 0,
                cumulativeBalance: nil
            )
        }
    }

    /// Build PeriodDataPoint array from MonthlyFinancialAggregate records.
    /// Handles .year, .allTime, .month, and .quarter by grouping monthly rows into buckets.
    private func computePeriodDataPointsFromAggregates(
        _ aggregates: [MonthlyFinancialAggregate],
        granularity: InsightGranularity,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> [PeriodDataPoint] {
        var incomeByKey = [String: Double]()
        var expensesByKey = [String: Double]()

        for agg in aggregates {
            guard let monthDate = calendar.date(
                from: DateComponents(year: agg.year, month: agg.month, day: 1)
            ) else { continue }
            let key = granularity.groupingKey(for: monthDate)
            incomeByKey[key, default: 0] += agg.totalIncome
            expensesByKey[key, default: 0] += agg.totalExpenses
        }

        // Determine canonical ordered keys from cursor walk (same as main path)
        var orderedKeys: [String] = []
        var keySet = Set<String>()
        var cursor = windowStart
        while cursor < windowEnd {
            let key = granularity.groupingKey(for: cursor)
            if !keySet.contains(key) {
                orderedKeys.append(key)
                keySet.insert(key)
            }
            switch granularity {
            case .year:    cursor = calendar.date(byAdding: .year,       value: 1, to: cursor) ?? windowEnd
            case .month:   cursor = calendar.date(byAdding: .month,      value: 1, to: cursor) ?? windowEnd
            case .quarter: cursor = calendar.date(byAdding: .month,      value: 3, to: cursor) ?? windowEnd
            case .allTime: cursor = windowEnd
            default:       cursor = windowEnd
            }
        }

        return orderedKeys.map { key in
            let periodStart = granularity.periodStart(for: key)
            let periodEnd: Date
            switch granularity {
            case .year:    periodEnd = calendar.date(byAdding: .year,  value: 1, to: periodStart) ?? periodStart
            case .month:   periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart
            case .quarter: periodEnd = calendar.date(byAdding: .month, value: 3, to: periodStart) ?? periodStart
            case .allTime: periodEnd = windowEnd
            default:       periodEnd = windowEnd
            }
            return PeriodDataPoint(
                id: key,
                granularity: granularity,
                key: key,
                periodStart: periodStart,
                periodEnd: periodEnd,
                label: granularity.periodLabel(for: key),
                income: incomeByKey[key] ?? 0,
                expenses: expensesByKey[key] ?? 0,
                cumulativeBalance: nil
            )
        }
    }

    // MARK: - Shared Helpers
    // Internal (no `private`) so cross-file extensions can call them.

    /// Lightweight summary value type used internally to avoid constructing the full `Summary` model.
    /// We cannot use `Summary` directly because it requires fields (currency, startDate, endDate,
    /// plannedAmount, totalInternalTransfers) that are irrelevant here and would force us to call
    /// `queryService.calculateSummary` — which hits the contaminating global cache.
    struct PeriodSummary {
        let totalIncome: Double
        let totalExpenses: Double
        let netFlow: Double
    }

    /// Returns the amount in baseCurrency. Uses cached convertedAmount when available.
    func resolveAmount(_ transaction: Transaction, baseCurrency: String) -> Double {
        guard transaction.currency != baseCurrency else { return transaction.amount }
        return transaction.convertedAmount ?? transaction.amount
    }

    /// Inline helper to avoid Calendar extension conflicts with Date+Helpers.swift.
    func startOfMonth(_ calendar: Calendar, for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Calculates income/expenses for a specific transaction slice WITHOUT using
    /// the global TransactionCacheManager cache.
    ///
    /// ROOT CAUSE FIX for identical monthly data:
    /// `TransactionQueryService.calculateSummary` has a global summary cache in
    /// `cacheManager.cachedSummary`. The first call for month[0] populates it;
    /// every subsequent call for months[1..5] hits `!summaryCacheInvalidated` and
    /// returns the cached month[0] result — even though a different transaction
    /// slice was passed. Since each monthly slice is independent, we must bypass
    /// the cache entirely and do the arithmetic directly.
    private func calculateMonthlySummary(
        transactions: [Transaction],
        baseCurrency: String,
        currencyService: TransactionCurrencyService
    ) -> (income: Double, expenses: Double) {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatters.dateFormatter
        var income: Double = 0
        var expenses: Double = 0

        for tx in transactions {
            guard let txDate = dateFormatter.date(from: tx.date), txDate <= today else { continue }
            let amount = currencyService.getConvertedAmountOrCompute(transaction: tx, to: baseCurrency)
            switch tx.type {
            case .income:  income += amount
            case .expense: expenses += amount
            default: break
            }
        }
        return (income, expenses)
    }

    /// Converts a recurring series amount to monthly equivalent in baseCurrency.
    func seriesMonthlyEquivalent(_ series: RecurringSeries, baseCurrency: String) -> Double {
        let amount = NSDecimalNumber(decimal: series.amount).doubleValue
        let rawMonthly: Double
        switch series.frequency {
        case .daily:   rawMonthly = amount * 30
        case .weekly:  rawMonthly = amount * 4.33
        case .monthly: rawMonthly = amount
        case .yearly:  rawMonthly = amount / 12
        }
        if series.currency != baseCurrency,
           let converted = CurrencyConverter.convertSync(amount: rawMonthly, from: series.currency, to: baseCurrency) {
            return converted
        }
        return rawMonthly
    }

    /// Phase 23-C P12: shared monthly recurring net calculation.
    /// Was duplicated verbatim in generateCashFlowInsights and generateCashFlowInsightsFromPeriodPoints.
    @MainActor
    func monthlyRecurringNet(baseCurrency: String) -> Double {
        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive }
        return activeSeries.reduce(0.0) { total, series in
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let monthly: Double
            switch series.frequency {
            case .daily:   monthly = amount * 30
            case .weekly:  monthly = amount * 4.33
            case .monthly: monthly = amount
            case .yearly:  monthly = amount / 12
            }
            let isIncome = transactionStore.categories.first { $0.name == series.category }?.type == .income
            return total + (isIncome ? monthly : -monthly)
        }
    }
}
