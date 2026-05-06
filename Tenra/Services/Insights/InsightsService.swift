//
//  InsightsService.swift
//  Tenra
//
//  Core InsightsService: class declaration, init, public API, granularity API,
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

nonisolated final class InsightsService {

    // MARK: - Logger
    // Internal so cross-file extensions can log with `Self.logger`.
    static let logger = Logger(subsystem: "Tenra", category: "InsightsService")

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
        // Locale-aware full-month-name template — renders "May 2026" / "май 2026"
        // instead of the previous "MMM yyyy" abbreviation.
        f.locale = .current
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMMyyyy", options: 0, locale: .current)
            ?? "MMMM yyyy"
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

    nonisolated func invalidateCache() {
        cache.invalidateAll()
    }

    // MARK: - Period Data Points (monthly granularity for CashFlow insights)

    /// Builds `[PeriodDataPoint]` for the given number of calendar months ending at `anchorDate`.
    /// Builds `[PeriodDataPoint]` for CashFlow insights.
    nonisolated func computeMonthlyPeriodDataPoints(
        transactions: [Transaction],
        months: Int,
        baseCurrency: String,
        cacheManager: TransactionCacheManager, // kept for call-site compatibility; unused inside
        currencyService: TransactionCurrencyService,
        anchorDate: Date? = nil,
        txDateMap: [String: Date]? = nil
    ) -> [PeriodDataPoint] {
        let anchor   = anchorDate ?? Date()
        let calendar = Calendar.current
        var dataPoints: [PeriodDataPoint] = []
        dataPoints.reserveCapacity(months)
        Self.logger.debug("📅 [Insights] Monthly period points — scanning \(transactions.count) tx for \(months) months")

        for i in (0..<months).reversed() {
            guard
                let monthStart = calendar.date(byAdding: .month, value: -i, to: startOfMonth(calendar, for: anchor)),
                let monthEnd   = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            // Use txDateMap fast path (O(1) per tx) when available — avoids `months` O(N)
            // DateFormatter passes (16μs/tx × 19k × 12 = ~3.6s on cold path).
            let monthTx: [Transaction]
            if let txDateMap {
                monthTx = filterService.filterByTimeRange(transactions, start: monthStart, end: monthEnd, txDateMap: txDateMap)
            } else {
                monthTx = filterService.filterByTimeRange(transactions, start: monthStart, end: monthEnd)
            }
            let (inc, exp) = calculateMonthlySummary(
                transactions: monthTx,
                baseCurrency: baseCurrency
            )
            let key   = InsightGranularity.month.groupingKey(for: monthStart)
            let label = Self.monthYearFormatter.string(from: monthStart)
            dataPoints.append(PeriodDataPoint(
                id: key,
                granularity: .month,
                key: key,
                periodStart: monthStart,
                periodEnd: monthEnd,
                label: label,
                income: inc,
                expenses: exp,
                cumulativeBalance: nil
            ))
        }
        return dataPoints
    }

    // MARK: - Category Deep Dive

    nonisolated func generateCategoryDeepDive(
        categoryName: String,
        allTransactions: [Transaction],
        timeFilter: TimeFilter,
        comparisonFilter: TimeFilter? = nil,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> (subcategories: [SubcategoryBreakdownItem], prevBucketTotal: Double) {
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

        // Previous-bucket total for period comparison card
        var prevBucketTotal: Double = 0
        if let cf = comparisonFilter {
            let cfRange = cf.dateRange()
            prevBucketTotal = filterService
                .filterByTimeRange(allCategoryTransactions, start: cfRange.start, end: cfRange.end)
                .reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        }

        return (subcategories, prevBucketTotal)
    }

    // MARK: - Granularity-based API

    /// Generates all insights for a given granularity.
    /// Accepts pre-built `transactions` array — caller builds it once on MainActor.
    /// `sharedInsights` — granularity-independent insights computed once by caller;
    /// when provided, shared generators are skipped and these insights are merged in.
    nonisolated func generateAllInsights(
        granularity: InsightGranularity,
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        snapshot: DataSnapshot,
        firstTransactionDate: Date? = nil,          // hoisted by caller to avoid 5× O(N) re-scan
        preAggregated: PreAggregatedData? = nil,
        sharedInsights: [Insight]? = nil
    ) -> (insights: [Insight], periodPoints: [PeriodDataPoint]) {
        let genStart = ContinuousClock.now
        let hasShared = sharedInsights != nil
        // Pre-parsed date cache from PreAggregatedData
        let dateMap = preAggregated?.txDateMap

        // Determine the date window for this granularity.
        // For .week: last 52 weeks. For .month/.quarter/.year/.allTime: first tx → now (covers all).
        // Use the pre-computed value when provided; fall back to local scan if called standalone.
        let firstDate: Date?
        if let provided = firstTransactionDate {
            firstDate = provided
        } else {
            firstDate = allTransactions
                .compactMap { (dateMap?[$0.date]) ?? DateFormatters.dateFormatter.date(from: $0.date) }
                .min()
        }
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // Non-week granularities cover the full date range (first tx → now).
        // The filter is guaranteed no-op for these — skip the O(N) scan entirely.
        // .week has a 52-week window that genuinely filters out older transactions.
        let windowedTransactions: [Transaction]
        if granularity != .week {
            windowedTransactions = allTransactions
        } else if let map = dateMap {
            windowedTransactions = allTransactions.filter { tx in
                guard let d = map[tx.date], d >= windowStart, d < windowEnd else { return false }
                return true
            }
        } else {
            windowedTransactions = filterService.filterByTimeRange(allTransactions, start: windowStart, end: windowEnd)
        }

        // TimeFilter wrapping the window — passed to generators that use aggregate fetch ranges
        // and the MoM reference date helper.
        let granularityTimeFilter = TimeFilter(preset: .custom, startDate: windowStart, endDate: windowEnd)

        // For non-week granularities, derive income/expenses from PreAggregated totals
        // in O(M) dictionary value iteration instead of O(N) transaction scan with currency conversion.
        // .week still requires per-transaction scan (52-week window != month boundaries).
        let windowedIncome: Double
        let windowedExpenses: Double
        if let preAgg = preAggregated, granularity != .week {
            var totalInc: Double = 0
            var totalExp: Double = 0
            for totals in preAgg.monthlyTotals.values {
                totalInc += totals.income
                totalExp += totals.expenses
            }
            windowedIncome = totalInc
            windowedExpenses = totalExp
        } else {
            let (wi, we) = calculateMonthlySummary(
                transactions: windowedTransactions,
                baseCurrency: baseCurrency,
                txDateMap: dateMap
            )
            windowedIncome = wi
            windowedExpenses = we
        }
        let periodSummary = PeriodSummary(
            totalIncome: windowedIncome,
            totalExpenses: windowedExpenses,
            netFlow: windowedIncome - windowedExpenses
        )

        // For non-week granularities, build period data points from PreAggregated's
        // monthly totals — O(months) lookups instead of O(N) transaction scan with Calendar+currency ops.
        // .week requires per-transaction scan (weekly buckets != monthly resolution).
        let periodPoints: [PeriodDataPoint]
        if let preAgg = preAggregated, granularity != .week {
            periodPoints = computePeriodDataPointsFromPreAggregated(
                preAggregated: preAgg,
                granularity: granularity,
                firstTransactionDate: firstDate
            )
        } else {
            periodPoints = computePeriodDataPoints(
                transactions: allTransactions,
                granularity: granularity,
                baseCurrency: baseCurrency,
                firstTransactionDate: firstDate,
                txDateMap: dateMap
            )
        }

        // Timing — setup (filter + summary + periodPoints)
        let setupDur = genStart.duration(to: .now)
        let setupMs = Int(setupDur.components.seconds * 1000) + Int(setupDur.components.attoseconds / 1_000_000_000_000_000)
        Self.logger.debug("⏱ [Insights] .\(granularity.rawValue, privacy: .public) setup: \(setupMs)ms (filter+summary+pts, shared=\(hasShared))")

        let genPhaseStart = ContinuousClock.now
        var insights: [Insight] = []

        // ── Granularity-DEPENDENT generators (always compute) ──────────────

        // Pass txDateMap to avoid date re-parsing; preAggregated so .allTime uses O(1) categoryTotals lookup
        insights.append(contentsOf: generateSpendingInsights(
            filtered: windowedTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            granularity: granularity,
            periodPoints: periodPoints,
            txDateMap: dateMap,
            preAggregated: preAggregated,
            categories: snapshot.categories
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
            periodPoints: periodPoints,
            txDateMap: dateMap
        ))

        insights.append(contentsOf: generateBudgetInsights(
            transactions: windowedTransactions,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency,
            categories: snapshot.categories
        ))

        insights.append(contentsOf: generateRecurringInsights(
            baseCurrency: baseCurrency,
            granularity: granularity,
            recurringSeries: snapshot.recurringSeries
        ))

        insights.append(contentsOf: generateCashFlowInsightsFromPeriodPoints(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            snapshot: snapshot
        ))

        // Pass accountTransactionCounts to avoid O(N*M) filter loop
        insights.append(contentsOf: generateWealthInsights(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            balanceFor: snapshot.balanceFor,
            accountTransactionCounts: preAggregated?.accountTransactionCounts,
            accounts: snapshot.accounts
        ))

        // SavingsRate is granularity-dependent — narrow to the current bucket so
        // the percentage answers "what fraction of THIS month/quarter/year/week
        // did I keep" rather than the whole data window. EmergencyFund is shared.
        let currentBucketPoint = periodPoints.first(where: { $0.key == granularity.currentPeriodKey })
        let bucketIncome = currentBucketPoint?.income ?? windowedIncome
        let bucketExpenses = currentBucketPoint?.expenses ?? windowedExpenses
        insights.append(contentsOf: generateSavingsInsights(
            allIncome: bucketIncome,
            allExpenses: bucketExpenses,
            bucketLabel: granularity.currentBucketLabel(),
            baseCurrency: baseCurrency,
            balanceFor: snapshot.balanceFor,
            accounts: snapshot.accounts,
            transactions: allTransactions,
            preAggregated: preAggregated,
            skipSharedGenerators: hasShared
        ))

        // Narrow incomeSourceBreakdown to current granularity bucket only.
        // Use dateMap for O(1) date lookups — avoids O(N) DateFormatter re-parsing.
        let currentBucketForForecasting: [Transaction]
        if let cp = periodPoints.first(where: { $0.key == granularity.currentPeriodKey }) {
            if let map = dateMap {
                currentBucketForForecasting = allTransactions.filter { tx in
                    guard let d = map[tx.date], d >= cp.periodStart, d < cp.periodEnd else { return false }
                    return true
                }
            } else {
                currentBucketForForecasting = filterService.filterByTimeRange(
                    allTransactions, start: cp.periodStart, end: cp.periodEnd
                )
            }
        } else {
            currentBucketForForecasting = windowedTransactions
        }

        // IncomeSourceBreakdown is granularity-dependent; rest are shared
        insights.append(contentsOf: generateForecastingInsights(
            allTransactions: allTransactions,
            baseCurrency: baseCurrency,
            snapshot: snapshot,
            filteredTransactions: currentBucketForForecasting,
            preAggregated: preAggregated,
            skipSharedGenerators: hasShared
        ))

        // ── Granularity-INDEPENDENT generators ─────────────────────────────
        // Compute only on first granularity; subsequent iterations
        // receive pre-computed results via sharedInsights parameter.

        // categoryTrend + subscriptionGrowth are granularity-dependent (lookback scales) —
        // always recompute. The remaining generators are still cached via sharedInsights.
        if let trend = generateCategoryTrend(baseCurrency: baseCurrency, granularity: granularity, transactions: allTransactions, preAggregated: preAggregated) {
            insights.append(trend)
        }
        if let growth = generateSubscriptionGrowth(baseCurrency: baseCurrency, granularity: granularity, recurringSeries: snapshot.recurringSeries, seriesMonthlyEquivalents: preAggregated?.seriesMonthlyEquivalents) {
            insights.append(growth)
        }

        if !hasShared {
            // Spending behavioral
            if let spike = generateSpendingSpike(baseCurrency: baseCurrency, transactions: allTransactions, preAggregated: preAggregated) {
                insights.append(spike)
            }
            // Recurring behavioral — pass pre-computed monthly equivalents from PreAggregatedData
            // so generators skip the per-series CurrencyConverter.convertSync call.
            if let duplicates = generateDuplicateSubscriptions(baseCurrency: baseCurrency, recurringSeries: snapshot.recurringSeries, seriesMonthlyEquivalents: preAggregated?.seriesMonthlyEquivalents) {
                insights.append(duplicates)
            }
            if let dormancy = generateAccountDormancy(allTransactions: allTransactions, balanceFor: snapshot.balanceFor, preAggregated: preAggregated, accounts: snapshot.accounts) {
                insights.append(dormancy)
            }
        } else {
            // Merge pre-computed shared insights
            insights.append(contentsOf: sharedInsights!)
        }

        // Timing — generators
        let genPhaseDur = genPhaseStart.duration(to: .now)
        let genPhaseMs = Int(genPhaseDur.components.seconds * 1000) + Int(genPhaseDur.components.attoseconds / 1_000_000_000_000_000)
        let totalGenDur = genStart.duration(to: .now)
        let totalGenMs = Int(totalGenDur.components.seconds * 1000) + Int(totalGenDur.components.attoseconds / 1_000_000_000_000_000)
        Self.logger.debug("⏱ [Insights] .\(granularity.rawValue, privacy: .public) generators: \(genPhaseMs)ms, total: \(totalGenMs)ms")

        return (insights, periodPoints)
    }

    /// Computes a specific subset of granularities. Used by progressive loading in InsightsViewModel:
    /// pass 1 computes the priority granularity for immediate display; pass 2 computes the rest.
    /// Builds PreAggregatedData once and passes to all granularity calls.
    /// Computes granularity-independent ("shared") insights on the FIRST granularity,
    /// then reuses them for subsequent granularities — eliminates 4x redundant generator runs.
    ///
    /// Returns: `(results, sharedInsights)` — caller should pass `sharedInsights` from pass 1
    /// into pass 2 via the `sharedInsights` parameter.
    nonisolated func computeGranularities(
        _ granularities: [InsightGranularity],
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        snapshot: DataSnapshot,
        firstTransactionDate: Date?,
        preAggregated: PreAggregatedData? = nil,
        sharedInsights: [Insight]? = nil
    ) -> (results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])], sharedInsights: [Insight]) {
        // Build PreAggregatedData once — single O(N) pass replaces ~10x O(N) scans per granularity
        let aggregated = preAggregated ?? PreAggregatedData.build(from: allTransactions, baseCurrency: baseCurrency)

        var shared = sharedInsights
        var results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])] = [:]

        for gran in granularities {
            let result = generateAllInsights(
                granularity: gran,
                transactions: allTransactions,
                baseCurrency: baseCurrency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                snapshot: snapshot,
                firstTransactionDate: aggregated.firstDate ?? firstTransactionDate,
                preAggregated: aggregated,
                sharedInsights: shared
            )

            // After the first granularity, extract shared insights for reuse
            if shared == nil {
                shared = Self.extractSharedInsights(from: result.insights)
                Self.logger.debug("🔗 [Insights] Extracted \(shared?.count ?? 0) shared insights from .\(gran.rawValue, privacy: .public)")
            }

            results[gran] = result
        }

        return (results, shared ?? [])
    }

    // MARK: - Shared Insight Extraction

    /// IDs of granularity-independent insights that produce identical results regardless of
    /// which granularity (week/month/quarter/year/allTime) is being computed.
    /// These are computed once on the first granularity and reused for all subsequent ones.
    private static let sharedInsightIDs: Set<String> = [
        "spending_spike",
        // "subscription_growth" — now granularity-dependent (lookback scales)
        "duplicate_subscriptions",
        "accountDormancy",
        "emergency_fund",
        "spending_forecast",
        "balance_runway",
        "year_over_year"
    ]

    /// Extracts granularity-independent insights from a full insight array.
    /// `category_trend_*` and `subscription_growth` were removed from the shared
    /// set — they now scale their lookback by granularity and must regenerate.
    static func extractSharedInsights(from insights: [Insight]) -> [Insight] {
        insights.filter { sharedInsightIDs.contains($0.id) }
    }

    /// Computes all insight granularities in a single call.
    /// Called once from InsightsViewModel.loadInsightsBackground() to replace
    /// the 5-iteration for-loop that caused 5 separate main actor hops.
    nonisolated func computeAllGranularities(
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        snapshot: DataSnapshot,
        firstTransactionDate: Date?,
        preAggregated: PreAggregatedData? = nil
    ) -> (results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])], sharedInsights: [Insight]) {
        return computeGranularities(
            InsightGranularity.allCases,
            transactions: allTransactions,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            snapshot: snapshot,
            firstTransactionDate: firstTransactionDate,
            preAggregated: preAggregated
        )
    }

    // MARK: - Period Data Points

    /// Groups all transactions into PeriodDataPoint buckets according to granularity.
    nonisolated func computePeriodDataPoints(
        transactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        firstTransactionDate: Date? = nil,
        txDateMap: [String: Date]? = nil
    ) -> [PeriodDataPoint] {
        let dateFormatter = Self.yearMonthFormatter
        let calendar = Calendar.current

        // Determine data window
        let firstDate = firstTransactionDate
            ?? transactions.compactMap { (txDateMap?[$0.date]) ?? dateFormatter.date(from: $0.date) }.min()
            ?? Date()
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // All transactions are in memory — direct scan for all granularities.
        guard !transactions.isEmpty else { return [] }

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
            // Use pre-parsed date when available (O(1) lookup vs O(DateFormatter))
            let txDate: Date?
            if let map = txDateMap {
                txDate = map[tx.date]
            } else {
                txDate = dateFormatter.date(from: tx.date)
            }
            guard let date = txDate, date >= windowStart, date < windowEnd else { continue }
            let key = granularity.groupingKey(for: date)
            let amount = resolveAmount(tx, baseCurrency: baseCurrency)
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

    // MARK: - Period Data Points from PreAggregated

    /// Builds period data points from PreAggregatedData's monthly totals.
    /// O(M) dictionary lookups (M = months in window) instead of O(N) transaction scans.
    /// For .month: direct 1:1 mapping (MonthKey → PeriodDataPoint).
    /// For .quarter/.year: aggregates 3/12 monthly totals per period.
    /// For .allTime: aggregates all monthly totals into one point.
    /// .week MUST NOT use this (weekly resolution ≠ monthly) — caller checks granularity.
    private nonisolated func computePeriodDataPointsFromPreAggregated(
        preAggregated: PreAggregatedData,
        granularity: InsightGranularity,
        firstTransactionDate: Date?
    ) -> [PeriodDataPoint] {
        let calendar = Calendar.current
        let firstDate = firstTransactionDate ?? preAggregated.firstDate ?? Date()
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // Build ordered period keys (same key-building logic as computePeriodDataPoints)
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
            case .week:    cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? windowEnd
            case .month:   cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? windowEnd
            case .quarter: cursor = calendar.date(byAdding: .month, value: 3, to: cursor) ?? windowEnd
            case .year:    cursor = calendar.date(byAdding: .year, value: 1, to: cursor) ?? windowEnd
            case .allTime: cursor = windowEnd
            }
        }

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

            // Sum monthly totals within [periodStart, periodEnd) — O(months_in_period) lookups
            let monthTotals = preAggregated.monthlyTotalsInRange(from: periodStart, to: periodEnd)
            let income = monthTotals.reduce(0.0) { $0 + $1.totalIncome }
            let expenses = monthTotals.reduce(0.0) { $0 + $1.totalExpenses }

            return PeriodDataPoint(
                id: key,
                granularity: granularity,
                key: key,
                periodStart: periodStart,
                periodEnd: periodEnd,
                label: granularity.periodLabel(for: key),
                income: income,
                expenses: expenses,
                cumulativeBalance: nil
            )
        }
    }

    // MARK: - Shared Helpers
    // Internal (no `private`) so cross-file extensions can call them.

    /// Lightweight summary value type used internally to avoid constructing the full `Summary` model.
    struct PeriodSummary {
        let totalIncome: Double
        let totalExpenses: Double
        let netFlow: Double
    }

    /// Snapshot of all MainActor-isolated data, captured once before background computation.
    /// Eliminates 30+ direct `transactionStore` accesses across extension files,
    /// enabling InsightsService to run fully off the main thread.
    struct DataSnapshot: Sendable {
        let transactions: [Transaction]
        let categories: [CustomCategory]
        let recurringSeries: [RecurringSeries]
        let accounts: [Account]
        let balanceFor: @Sendable (String) -> Double
    }

    // MARK: - In-Memory Aggregate Helpers

    /// Monthly income/expense totals computed from in-memory transactions.
    struct InMemoryMonthlyTotal {
        let year: Int
        let month: Int
        let totalIncome: Double
        let totalExpenses: Double
        var netFlow: Double { totalIncome - totalExpenses }
        var label: String {
            guard let date = Calendar.current.date(
                from: DateComponents(year: year, month: month, day: 1)
            ) else { return "\(month)/\(year)" }
            return InsightsService.monthYearFormatter.string(from: date)
        }
    }

    /// Per-category expense totals for a specific (year, month) computed from in-memory transactions.
    struct InMemoryCategoryMonthTotal {
        let categoryName: String
        let year: Int
        let month: Int
        let totalExpenses: Double
    }

    /// Groups transactions by (year, month) and returns income/expense totals sorted chronologically.
    /// Replaces MonthlyAggregateService.fetchRange().
    static func computeMonthlyTotals(
        from transactions: [Transaction],
        from startDate: Date,
        to endDate: Date,
        baseCurrency: String
    ) -> [InMemoryMonthlyTotal] {
        let calendar = Calendar.current
        let df = DateFormatters.dateFormatter
        struct Key: Hashable { let year: Int; let month: Int }
        var acc: [Key: (income: Double, expenses: Double)] = [:]

        for tx in transactions {
            guard tx.type == .income || tx.type == .expense else { continue }
            guard let txDate = df.date(from: tx.date),
                  txDate >= startDate, txDate < endDate else { continue }
            let comps = calendar.dateComponents([.year, .month], from: txDate)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = Key(year: year, month: month)
            let amount = resolveAmountStatic(tx, baseCurrency: baseCurrency)
            switch tx.type {
            case .income:  acc[key, default: (0, 0)].income += amount
            case .expense: acc[key, default: (0, 0)].expenses += amount
            default: break
            }
        }

        return acc.map { key, val in
            InMemoryMonthlyTotal(year: key.year, month: key.month, totalIncome: val.income, totalExpenses: val.expenses)
        }
        .sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }
    }

    /// Returns monthly totals for the last `n` months ending at `anchor`.
    /// Equivalent to MonthlyAggregateService.fetchLast(_:anchor:currency:).
    static func computeLastMonthlyTotals(
        _ months: Int,
        from transactions: [Transaction],
        anchor: Date = Date(),
        baseCurrency: String
    ) -> [InMemoryMonthlyTotal] {
        let calendar = Calendar.current
        let anchorMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: anchor)
        ) ?? anchor
        guard
            let startDate = calendar.date(byAdding: .month, value: -(months - 1), to: anchorMonthStart),
            let endDateExclusive = calendar.date(byAdding: .month, value: 1, to: anchorMonthStart)
        else { return [] }
        return computeMonthlyTotals(from: transactions, from: startDate, to: endDateExclusive, baseCurrency: baseCurrency)
    }

    /// Groups expense transactions by (category, year, month) and returns totals sorted chronologically.
    /// Replaces CategoryAggregateService.fetchRange().
    static func computeCategoryMonthTotals(
        from transactions: [Transaction],
        from startDate: Date,
        to endDate: Date,
        baseCurrency: String
    ) -> [InMemoryCategoryMonthTotal] {
        let calendar = Calendar.current
        let df = DateFormatters.dateFormatter
        struct Key: Hashable { let category: String; let year: Int; let month: Int }
        var acc: [Key: Double] = [:]

        for tx in transactions {
            guard tx.type == .expense, !tx.category.isEmpty else { continue }
            guard let txDate = df.date(from: tx.date),
                  txDate >= startDate, txDate < endDate else { continue }
            let comps = calendar.dateComponents([.year, .month], from: txDate)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = Key(category: tx.category, year: year, month: month)
            acc[key, default: 0] += resolveAmountStatic(tx, baseCurrency: baseCurrency)
        }

        return acc.map { key, expenses in
            InMemoryCategoryMonthTotal(categoryName: key.category, year: key.year, month: key.month, totalExpenses: expenses)
        }
        .sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }
    }

    // MARK: - PreAggregatedData — Single O(N) Pass

    /// Pre-aggregated monthly and category-monthly totals built from a single O(N) pass.
    /// Each generator calls O(M) dictionary lookups (M = months) instead of O(N).
    ///
    /// Usage: build once via `PreAggregatedData.build(from:baseCurrency:)` before the generator loop,
    /// then pass to generators. Each generator calls O(M) dictionary lookups (M = months) instead of O(N).
    struct PreAggregatedData: Sendable {
        struct MonthKey: Hashable, Sendable {
            let year: Int
            let month: Int
        }
        struct CategoryMonthKey: Hashable, Sendable {
            let category: String
            let year: Int
            let month: Int
        }
        struct MonthTotals: Sendable {
            var income: Double
            var expenses: Double
            var netFlow: Double { income - expenses }
        }

        let monthlyTotals: [MonthKey: MonthTotals]
        let categoryMonthExpenses: [CategoryMonthKey: Double]
        let firstDate: Date?
        let lastDate: Date?
        /// Pre-parsed date strings -> Date. Keyed by date STRING (not tx.id)
        /// since many transactions share the same date.
        /// Eliminates O(DateFormatter) re-parsing across all generators.
        let txDateMap: [String: Date]
        /// Pre-computed per-account transaction counts. O(1) lookup replaces
        /// O(N*M) allTransactions.filter { $0.accountId == id }.count in wealth generator.
        let accountTransactionCounts: [String: Int]
        /// Pre-computed last transaction date per account. O(1) lookup replaces
        /// O(N) DateFormatter loop in generateAccountDormancy.
        let lastAccountDates: [String: Date]
        /// Total expense per category across ALL transactions. O(1) lookup
        /// for .allTime generator — replaces O(N) Dictionary(grouping:) + map { resolveAmount }.
        let categoryTotals: [String: Double]
        /// Pre-computed monthly equivalent per recurring series id, in `baseCurrency`.
        /// Built when `recurringSeries` is passed to `build`. Empty otherwise — callers
        /// then fall back to `seriesMonthlyEquivalent(_:baseCurrency:)`.
        /// Eliminates N×CurrencyConverter.convertSync calls in HealthScore / Recurring /
        /// Forecasting generators (each runs on every insights recompute).
        let seriesMonthlyEquivalents: [String: Double]

        // MARK: Helpers (O(M) dictionary lookups, not O(N) scans)

        /// Returns monthly totals within a date range, sorted chronologically.
        func monthlyTotalsInRange(from start: Date, to end: Date) -> [InMemoryMonthlyTotal] {
            let calendar = Calendar.current
            var results: [InMemoryMonthlyTotal] = []
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            while cursor < end {
                let comps = calendar.dateComponents([.year, .month], from: cursor)
                guard let year = comps.year, let month = comps.month else { break }
                let key = MonthKey(year: year, month: month)
                if let totals = monthlyTotals[key] {
                    results.append(InMemoryMonthlyTotal(
                        year: year, month: month,
                        totalIncome: totals.income, totalExpenses: totals.expenses
                    ))
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            return results
        }

        /// Returns monthly totals for the last `n` months ending at `anchor`.
        func lastMonthlyTotals(_ months: Int, anchor: Date = Date()) -> [InMemoryMonthlyTotal] {
            let calendar = Calendar.current
            let anchorMonthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: anchor)
            ) ?? anchor
            guard let startDate = calendar.date(byAdding: .month, value: -(months - 1), to: anchorMonthStart),
                  let endDateExclusive = calendar.date(byAdding: .month, value: 1, to: anchorMonthStart)
            else { return [] }
            return monthlyTotalsInRange(from: startDate, to: endDateExclusive)
        }

        /// Returns category-monthly expense totals within a date range, sorted chronologically.
        func categoryMonthTotalsInRange(from start: Date, to end: Date) -> [InMemoryCategoryMonthTotal] {
            let calendar = Calendar.current
            var categorySet = Set<String>()
            for key in categoryMonthExpenses.keys { categorySet.insert(key.category) }
            var results: [InMemoryCategoryMonthTotal] = []
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            while cursor < end {
                let comps = calendar.dateComponents([.year, .month], from: cursor)
                guard let year = comps.year, let month = comps.month else { break }
                for category in categorySet {
                    let key = CategoryMonthKey(category: category, year: year, month: month)
                    if let expenses = categoryMonthExpenses[key] {
                        results.append(InMemoryCategoryMonthTotal(
                            categoryName: category, year: year, month: month, totalExpenses: expenses
                        ))
                    }
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            return results.sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }
        }

        // MARK: Builder

        static func build(
            from transactions: [Transaction],
            baseCurrency: String,
            recurringSeries: [RecurringSeries] = []
        ) -> PreAggregatedData {
            let calendar = Calendar.current
            let df = DateFormatters.dateFormatter
            var monthly = [MonthKey: MonthTotals]()
            var categoryMonth = [CategoryMonthKey: Double]()
            var firstDate: Date?
            var lastDate: Date?
            var dateMap = [String: Date]()
            var accountCounts = [String: Int]()
            var lastAccountDates = [String: Date]()
            var categoryTotals = [String: Double]()

            for tx in transactions {
                // Cache date parsing — each unique date string parsed exactly once
                let txDate: Date
                if let cached = dateMap[tx.date] {
                    txDate = cached
                } else if let parsed = df.date(from: tx.date) {
                    dateMap[tx.date] = parsed
                    txDate = parsed
                } else {
                    continue
                }

                if firstDate == nil || txDate < firstDate! { firstDate = txDate }
                if lastDate == nil || txDate > lastDate! { lastDate = txDate }

                // Count transactions per account and track last transaction date (for dormancy detection)
                if let accountId = tx.accountId, !accountId.isEmpty {
                    accountCounts[accountId, default: 0] += 1
                    if let existing = lastAccountDates[accountId] {
                        if txDate > existing { lastAccountDates[accountId] = txDate }
                    } else {
                        lastAccountDates[accountId] = txDate
                    }
                }

                guard tx.type == .income || tx.type == .expense else { continue }
                let comps = calendar.dateComponents([.year, .month], from: txDate)
                guard let year = comps.year, let month = comps.month else { continue }
                let monthKey = MonthKey(year: year, month: month)
                let amount = resolveAmountStatic(tx, baseCurrency: baseCurrency)

                switch tx.type {
                case .income:
                    monthly[monthKey, default: MonthTotals(income: 0, expenses: 0)].income += amount
                case .expense:
                    monthly[monthKey, default: MonthTotals(income: 0, expenses: 0)].expenses += amount
                    if !tx.category.isEmpty {
                        let catKey = CategoryMonthKey(category: tx.category, year: year, month: month)
                        categoryMonth[catKey, default: 0] += amount
                        // Accumulate all-time category total (piggyback on existing loop)
                        categoryTotals[tx.category, default: 0] += amount
                    }
                default: break
                }
            }

            // Pre-compute monthly equivalent per recurring series. CurrencyConverter.convertSync
            // is called O(K) times here (K = recurring series count, typically 5–30) instead
            // of K × G times across G generators (HealthScore + Recurring + Forecasting).
            var seriesMonthly = [String: Double]()
            seriesMonthly.reserveCapacity(recurringSeries.count)
            for series in recurringSeries {
                seriesMonthly[series.id] = InsightsService.computeSeriesMonthlyEquivalent(series, baseCurrency: baseCurrency)
            }

            return PreAggregatedData(
                monthlyTotals: monthly,
                categoryMonthExpenses: categoryMonth,
                firstDate: firstDate,
                lastDate: lastDate,
                txDateMap: dateMap,
                accountTransactionCounts: accountCounts,
                lastAccountDates: lastAccountDates,
                categoryTotals: categoryTotals,
                seriesMonthlyEquivalents: seriesMonthly
            )
        }
    }

    /// Amount resolver for static helper methods (no `self` needed).
    /// Converts `tx.amount` from `tx.currency` into `baseCurrency` via the live
    /// FX cache. Uses `convertedAmount` (in *account* currency) only as a
    /// last-resort fallback when rates are unavailable.
    static func resolveAmountStatic(_ tx: Transaction, baseCurrency: String) -> Double {
        guard tx.currency != baseCurrency else { return tx.amount }
        if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) {
            return fx
        }
        return tx.convertedAmount ?? tx.amount
    }

    /// Returns the amount in `baseCurrency` via `CurrencyConverter.convertSync`.
    /// `convertedAmount` is denominated in the account's currency and is therefore
    /// only a fallback for the cold-cache case.
    nonisolated func resolveAmount(_ transaction: Transaction, baseCurrency: String) -> Double {
        guard transaction.currency != baseCurrency else { return transaction.amount }
        if let fx = CurrencyConverter.convertSync(
            amount: transaction.amount,
            from: transaction.currency,
            to: baseCurrency
        ) {
            return fx
        }
        return transaction.convertedAmount ?? transaction.amount
    }

    /// Inline helper to avoid Calendar extension conflicts with Date+Helpers.swift.
    nonisolated func startOfMonth(_ calendar: Calendar, for date: Date) -> Date {
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
    private nonisolated func calculateMonthlySummary(
        transactions: [Transaction],
        baseCurrency: String,
        txDateMap: [String: Date]? = nil
    ) -> (income: Double, expenses: Double) {
        let today = Calendar.current.startOfDay(for: Date())
        // txDateMap fast path preferred; fallback allocates locally
        var income: Double = 0
        var expenses: Double = 0

        for tx in transactions {
            // Use pre-parsed date when available (O(1) lookup vs O(DateFormatter))
            let txDate: Date?
            if let map = txDateMap {
                txDate = map[tx.date]
            } else {
                // Fallback: allocate a formatter locally (rare path when preAggregated is nil)
                let fallbackDF = DateFormatter()
                fallbackDF.dateFormat = "yyyy-MM-dd"
                txDate = fallbackDF.date(from: tx.date)
            }
            guard let date = txDate, date <= today else { continue }
            let amount = resolveAmount(tx, baseCurrency: baseCurrency)
            switch tx.type {
            case .income:  income += amount
            case .expense: expenses += amount
            default: break
            }
        }
        return (income, expenses)
    }

    /// Converts a recurring series amount to monthly equivalent in baseCurrency.
    /// Pass `cache` (typically `preAggregated.seriesMonthlyEquivalents`) to skip the
    /// CurrencyConverter.convertSync call — pre-computed once during PreAggregatedData.build.
    nonisolated func seriesMonthlyEquivalent(
        _ series: RecurringSeries,
        baseCurrency: String,
        cache: [String: Double]? = nil
    ) -> Double {
        if let cached = cache?[series.id] { return cached }
        return Self.computeSeriesMonthlyEquivalent(series, baseCurrency: baseCurrency)
    }

    /// Static equivalent of `seriesMonthlyEquivalent` so it can be reused both as the
    /// instance method (legacy callers) and as the seed for `PreAggregatedData`'s
    /// pre-computed cache. Pure function — no `self` access — safe from any thread.
    nonisolated static func computeSeriesMonthlyEquivalent(_ series: RecurringSeries, baseCurrency: String) -> Double {
        let amount = NSDecimalNumber(decimal: series.amount).doubleValue
        let rawMonthly: Double
        switch series.frequency {
        case .daily:     rawMonthly = amount * 30
        case .weekly:    rawMonthly = amount * 4.33
        case .monthly:   rawMonthly = amount
        case .quarterly: rawMonthly = amount / 3
        case .yearly:    rawMonthly = amount / 12
        }
        if series.currency != baseCurrency,
           let converted = CurrencyConverter.convertSync(amount: rawMonthly, from: series.currency, to: baseCurrency) {
            return converted
        }
        return rawMonthly
    }

    /// Shared monthly recurring net calculation.
    /// Takes snapshot params instead of accessing transactionStore directly.
    nonisolated func monthlyRecurringNet(
        baseCurrency: String,
        recurringSeries: [RecurringSeries],
        categories: [CustomCategory]
    ) -> Double {
        let activeSeries = recurringSeries.filter { $0.isActive }
        return activeSeries.reduce(0.0) { total, series in
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let monthly: Double
            switch series.frequency {
            case .daily:     monthly = amount * 30
            case .weekly:    monthly = amount * 4.33
            case .monthly:   monthly = amount
            case .quarterly: monthly = amount / 3
            case .yearly:    monthly = amount / 12
            }
            let isIncome = categories.first { $0.name == series.category }?.type == .income
            return total + (isIncome ? monthly : -monthly)
        }
    }
}
