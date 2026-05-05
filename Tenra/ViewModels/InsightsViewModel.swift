//
//  InsightsViewModel.swift
//  Tenra
//

import Foundation
import SwiftUI
import Observation
import os

@Observable
@MainActor
final class InsightsViewModel {
    // MARK: - Logger

    private nonisolated static let logger = Logger(subsystem: "Tenra", category: "InsightsViewModel")

    // MARK: - Dependencies

    @ObservationIgnored private let insightsService: InsightsService
    @ObservationIgnored private let transactionStore: TransactionStore
    @ObservationIgnored private let transactionsViewModel: TransactionsViewModel

    // MARK: - Push-model cache

    /// Pre-computed insights keyed by granularity.
    /// Populated in background when data changes; read instantly on tab open.
    @ObservationIgnored private var precomputedInsights: [InsightGranularity: [Insight]] = [:]

    /// Pre-computed period data points keyed by granularity.
    @ObservationIgnored private var precomputedPeriodPoints: [InsightGranularity: [PeriodDataPoint]] = [:]

    /// Pre-computed period totals keyed by granularity.
    private struct PeriodTotals: Sendable {
        let income: Double
        let expenses: Double
        let netFlow: Double
        // Bucket-only slice (current + previous bucket).
        let currentBucketIncome: Double
        let currentBucketExpenses: Double
        let currentBucketNetFlow: Double
        let previousBucketIncome: Double
        let previousBucketExpenses: Double
        let previousBucketNetFlow: Double
    }
    @ObservationIgnored private var precomputedTotals: [InsightGranularity: PeriodTotals] = [:]

    /// Background recompute task handle — cancelled and replaced on each data change.
    @ObservationIgnored private var recomputeTask: Task<Void, Never>?

    /// Debounce task — coalesces rapid mutation bursts into a single recompute.
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// Used only as internal guard in onAppear().
    @ObservationIgnored private(set) var isStale: Bool = true

    /// Tracks whether Insights tab is currently visible.
    /// When not visible, invalidateAndRecompute() only marks stale (no background compute).
    @ObservationIgnored private var isVisible: Bool = false

    // MARK: - Observable State

    private(set) var insights: [Insight] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    var selectedCategory: InsightCategory? = nil
    private(set) var periodDataPoints: [PeriodDataPoint] = []
    private(set) var totalIncome: Double = 0
    private(set) var totalExpenses: Double = 0
    private(set) var netFlow: Double = 0
    // Current bucket totals (the actual current period — e.g. this month).
    // Distinct from totalIncome/totalExpenses/netFlow which are cumulative across
    // the data window used by charts.
    private(set) var currentBucketIncome: Double = 0
    private(set) var currentBucketExpenses: Double = 0
    private(set) var currentBucketNetFlow: Double = 0
    // Previous bucket totals — same period, one bucket earlier — for MoM delta.
    private(set) var previousBucketIncome: Double = 0
    private(set) var previousBucketExpenses: Double = 0
    private(set) var previousBucketNetFlow: Double = 0
    /// Localised label for the current bucket ("May 2026", "Q2 2026", "Last 7 days").
    private(set) var currentBucketLabel: String = ""
    /// Financial Health Score (computed once per recompute cycle, using .month granularity data)
    private(set) var healthScore: FinancialHealthScore? = nil

    // MARK: - Granularity (replaces TimeFilter for Insights)

    /// Settable from View via @Bindable — didSet handles applyPrecomputed side-effect.
    var currentGranularity: InsightGranularity = .month {
        didSet {
            guard oldValue != self.currentGranularity else { return }
            Self.logger.debug("🧠 [InsightsVM] granularity → \(self.currentGranularity.rawValue, privacy: .public)")
            if precomputedInsights[self.currentGranularity] != nil {
                self.applyPrecomputed(for: self.currentGranularity)
            } else {
                self.loadInsightsBackground()
            }
        }
    }

    /// Legacy: kept for CategoryDeepDive compatibility until it is migrated to granularity.
    private(set) var currentTimeFilter: TimeFilter = TimeFilter(preset: .allTime)

    // MARK: - Computed Properties

    var filteredInsights: [Insight] {
        guard let category = selectedCategory else { return insights }
        return insights.filter { $0.category == category }
    }

    private func sortedBySeverity(_ items: [Insight]) -> [Insight] {
        items.sorted { $0.severity.sortOrder < $1.severity.sortOrder }
    }

    var spendingInsights: [Insight]     { sortedBySeverity(insights.filter { $0.category == .spending }) }
    var incomeInsights: [Insight]       { sortedBySeverity(insights.filter { $0.category == .income }) }
    var budgetInsights: [Insight]       { sortedBySeverity(insights.filter { $0.category == .budget }) }
    var recurringInsights: [Insight]    { sortedBySeverity(insights.filter { $0.category == .recurring }) }
    var cashFlowInsights: [Insight]     { sortedBySeverity(insights.filter { $0.category == .cashFlow }) }
    var wealthInsights: [Insight]       { sortedBySeverity(insights.filter { $0.category == .wealth }) }
    var savingsInsights: [Insight]      { sortedBySeverity(insights.filter { $0.category == .savings }) }
    var forecastingInsights: [Insight]  { sortedBySeverity(insights.filter { $0.category == .forecasting }) }

    var baseCurrency: String {
        transactionStore.baseCurrency
    }

    var hasData: Bool {
        // Read the Observable scalar mirror (`transactionsCount`) instead of
        // `transactions.isEmpty`. The latter subscribes the entire 19k-tx array
        // and re-evaluates the whole Insights feed on every transaction mutation.
        transactionStore.transactionsCount > 0
    }

    // MARK: - Lifecycle

    deinit {
        recomputeTask?.cancel()
        debounceTask?.cancel()
    }

    // MARK: - Init

    init(
        insightsService: InsightsService,
        transactionStore: TransactionStore,
        transactionsViewModel: TransactionsViewModel
    ) {
        self.insightsService = insightsService
        self.transactionStore = transactionStore
        self.transactionsViewModel = transactionsViewModel
    }

    // MARK: - Public Methods

    /// Called when the user switches granularity (instant — reads precomputed data).
    func switchGranularity(_ granularity: InsightGranularity) {
        currentGranularity = granularity  // didSet handles guard + applyPrecomputed
    }

    /// Called when Insights tab appears — triggers computation if stale.
    /// When data is fresh, reads from precomputed cache (0ms).
    func onAppear() {
        isVisible = true
        if isStale || precomputedInsights[currentGranularity] == nil {
            Self.logger.debug("🧠 [InsightsVM] onAppear — stale or cache MISS, loading")
            isStale = false
            loadInsightsBackground()
        } else {
            Self.logger.debug("🧠 [InsightsVM] onAppear — cache HIT (instant)")
            applyPrecomputed(for: currentGranularity)
        }
    }

    /// Called when Insights tab disappears.
    func onDisappear() {
        isVisible = false
    }

    /// Marks stale and wipes caches.
    /// Only schedules background recompute when the Insights tab is currently visible.
    /// When not visible, onAppear() triggers recompute lazily when user navigates to Insights.
    /// When visible, debounces (800ms) and recomputes only the current granularity for speed.
    func invalidateAndRecompute() {
        Self.logger.debug("🔄 [InsightsVM] invalidateAndRecompute — marking stale (visible=\(self.isVisible))")
        insightsService.invalidateCache()
        precomputedInsights = [:]
        precomputedPeriodPoints = [:]
        precomputedTotals = [:]
        isStale = true
        recomputeTask?.cancel()
        debounceTask?.cancel()

        guard isVisible else { return }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.loadInsightsBackground()
        }
    }

    func invalidateCache() {
        invalidateAndRecompute()
    }

    /// Wipe caches directly and trigger immediate (non-debounced) background load.
    func refreshInsights() {
        Self.logger.debug("🔄 [InsightsVM] refreshInsights — manual refresh")
        insightsService.invalidateCache()
        precomputedInsights = [:]
        precomputedPeriodPoints = [:]
        precomputedTotals = [:]
        recomputeTask?.cancel()
        debounceTask?.cancel()
        isStale = false
        loadInsightsBackground()
    }

    func selectCategory(_ category: InsightCategory?) {
        selectedCategory = category
    }

    // MARK: - Category Deep Dive

    func categoryDeepDive(
        categoryName: String
    ) -> (subcategories: [SubcategoryBreakdownItem], prevBucketTotal: Double) {
        // Use current granularity bucket only (not the full window).
        let currentKey   = currentGranularity.currentPeriodKey
        let currentStart = currentGranularity.periodStart(for: currentKey)
        let currentEnd   = currentGranularity.periodEnd(for: currentKey)
        let currentFilter = TimeFilter(preset: .custom, startDate: currentStart, endDate: currentEnd)

        // Previous bucket — for the comparison card in InsightDeepDiveView.
        let prevKey   = currentGranularity.previousPeriodKey
        let prevStart = currentGranularity.periodStart(for: prevKey)
        let prevEnd   = currentStart   // prev bucket ends where current bucket begins
        let prevFilter = TimeFilter(preset: .custom, startDate: prevStart, endDate: prevEnd)

        // All transactions in memory — no window check needed.
        let allTransactions = Array(transactionStore.transactions)

        return insightsService.generateCategoryDeepDive(
            categoryName: categoryName,
            allTransactions: allTransactions,
            timeFilter: currentFilter,
            comparisonFilter: prevFilter,
            baseCurrency: baseCurrency,
            cacheManager: transactionsViewModel.cacheManager,
            currencyService: transactionsViewModel.currencyService
        )
    }

    // MARK: - Private: Background Loading

    /// Two-phase progressive loading.
    /// First computes only the current (priority) granularity and writes to UI immediately.
    /// Then computes the remaining granularities + health score, then does a final UI update.
    private func loadInsightsBackground() {
        // Guard against startup race — if transactions haven't loaded yet, stay stale.
        guard !transactionStore.transactions.isEmpty else { return }
        isStale = false
        debounceTask?.cancel()
        isLoading = true
        recomputeTask?.cancel()

        // Capture everything needed on the background thread while on MainActor
        let currency = baseCurrency
        let cacheManager = transactionsViewModel.cacheManager
        let currencyService = transactionsViewModel.currencyService
        let service = insightsService
        let allTransactions = Array(transactionStore.transactions)
        let balanceSnapshot = makeBalanceSnapshot()
        // Pre-capture @MainActor model snapshots for off-main-thread computation.
        let categoriesSnapshot  = Array(transactionStore.categories)
        let recurringSnapshot   = Array(transactionStore.recurringSeries)
        let accountsSnapshot    = Array(transactionStore.accounts)
        let priorityGranularity = currentGranularity  // show this one first
        // Bundle all snapshots into DataSnapshot for nonisolated computation
        let snapshot = InsightsService.DataSnapshot(
            transactions: allTransactions,
            categories: categoriesSnapshot,
            recurringSeries: recurringSnapshot,
            accounts: accountsSnapshot,
            balanceFor: { [balanceSnapshot] id in balanceSnapshot[id] ?? 0 }
        )

        recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    guard let self, self.isLoading else { return }
                    self.isLoading = false
                }
            }
            guard let self, !Task.isCancelled else { return }
            let totalStart = ContinuousClock.now
            Self.logger.debug("🔧 [InsightsVM] Background recompute START (detached)")

            // Build PreAggregatedData once — single O(N) pass for all granularities.
            // Pass `recurringSnapshot` so the build pre-computes `seriesMonthlyEquivalents`
            // (otherwise HealthScore + Recurring + Forecasting each call CurrencyConverter.convertSync per series).
            let preAggStart = ContinuousClock.now
            let preAggregated = InsightsService.PreAggregatedData.build(
                from: allTransactions,
                baseCurrency: currency,
                recurringSeries: recurringSnapshot
            )
            let preAggDur = preAggStart.duration(to: .now)
            let preAggMs = Int(preAggDur.components.seconds * 1000) + Int(preAggDur.components.attoseconds / 1_000_000_000_000_000)
            Self.logger.debug("⏱ [InsightsVM] PreAggregatedData.build(): \(preAggMs)ms")

            var newInsights = [InsightGranularity: [Insight]]()
            var newPoints   = [InsightGranularity: [PeriodDataPoint]]()
            var newTotals   = [InsightGranularity: PeriodTotals]()

            // ── Priority granularity → early UI update ──────────────
            guard !Task.isCancelled else { return }

            let p1Start = ContinuousClock.now
            let phase1Result = service.computeGranularities(
                [priorityGranularity],
                transactions: allTransactions,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                snapshot: snapshot,
                firstTransactionDate: preAggregated.firstDate,
                preAggregated: preAggregated,
                sharedInsights: nil
            )
            let p1Dur = p1Start.duration(to: .now)
            let p1Ms = Int(p1Dur.components.seconds * 1000) + Int(p1Dur.components.attoseconds / 1_000_000_000_000_000)
            // Capture shared insights for reuse in remaining granularities
            let sharedInsights = phase1Result.sharedInsights

            for gran in [priorityGranularity] {
                guard let result = phase1Result.results[gran] else { continue }
                let pts = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in pts { income += p.income; expenses += p.expenses }
                let curTotals = Self.bucketTotals(in: pts, forKey: gran.currentPeriodKey)
                let prevTotals = Self.bucketTotals(in: pts, forKey: gran.previousPeriodKey)
                newInsights[gran] = result.insights
                newPoints[gran]   = pts
                newTotals[gran]   = PeriodTotals(
                    income: income, expenses: expenses, netFlow: income - expenses,
                    currentBucketIncome: curTotals.income,
                    currentBucketExpenses: curTotals.expenses,
                    currentBucketNetFlow: curTotals.income - curTotals.expenses,
                    previousBucketIncome: prevTotals.income,
                    previousBucketExpenses: prevTotals.expenses,
                    previousBucketNetFlow: prevTotals.income - prevTotals.expenses
                )
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(pts.count) pts")
            }
            Self.logger.debug("⏱ [InsightsVM] Priority gran (.\(priorityGranularity.rawValue, privacy: .public)): \(p1Ms)ms — shared=\(sharedInsights.count)")

            guard !Task.isCancelled else { return }

            // Show the current granularity immediately — user sees real data, not zeros
            let phase1Insights = newInsights
            let phase1Points   = newPoints
            let phase1Totals   = newTotals
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.precomputedInsights     = phase1Insights
                self.precomputedPeriodPoints = phase1Points
                self.precomputedTotals       = phase1Totals
                self.applyPrecomputed(for: self.currentGranularity)
                Self.logger.debug("🔧 [InsightsVM] Priority gran done — .\(priorityGranularity.rawValue, privacy: .public) shown early")
            }

            // ── Remaining granularities ─────────────────────────────
            let remainingGrans = InsightGranularity.allCases.filter { $0 != priorityGranularity }
            guard !Task.isCancelled else { return }

            let p2Start = ContinuousClock.now
            let phase2Result = service.computeGranularities(
                remainingGrans,
                transactions: allTransactions,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                snapshot: snapshot,
                firstTransactionDate: preAggregated.firstDate,
                preAggregated: preAggregated,
                sharedInsights: sharedInsights
            )
            let p2Dur = p2Start.duration(to: .now)
            let p2Ms = Int(p2Dur.components.seconds * 1000) + Int(p2Dur.components.attoseconds / 1_000_000_000_000_000)
            Self.logger.debug("⏱ [InsightsVM] Remaining grans (\(remainingGrans.count)): \(p2Ms)ms")

            for (gran, result) in phase2Result.results {
                let pts = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in pts { income += p.income; expenses += p.expenses }
                let curTotals = Self.bucketTotals(in: pts, forKey: gran.currentPeriodKey)
                let prevTotals = Self.bucketTotals(in: pts, forKey: gran.previousPeriodKey)
                newInsights[gran] = result.insights
                newPoints[gran]   = pts
                newTotals[gran]   = PeriodTotals(
                    income: income, expenses: expenses, netFlow: income - expenses,
                    currentBucketIncome: curTotals.income,
                    currentBucketExpenses: curTotals.expenses,
                    currentBucketNetFlow: curTotals.income - curTotals.expenses,
                    previousBucketIncome: prevTotals.income,
                    previousBucketExpenses: prevTotals.expenses,
                    previousBucketNetFlow: prevTotals.income - prevTotals.expenses
                )
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(pts.count) pts")
            }

            guard !Task.isCancelled else { return }

            // Health score uses .month data (available after phase 2 if priority wasn't .month,
            // or from phase 1 if priority was .month)
            let monthTotals   = newTotals[.month]
            let monthPoints   = newPoints[.month] ?? []
            let latestNetFlow = monthPoints.last?.netFlow ?? 0
            let computedHealthScore = service.computeHealthScore(
                totalIncome: monthTotals?.income   ?? 0,
                totalExpenses: monthTotals?.expenses ?? 0,
                latestNetFlow: latestNetFlow,
                monthsInWindow: monthPoints.count,
                baseCurrency: currency,
                balanceFor: { balanceSnapshot[$0] ?? 0 },
                allTransactions: allTransactions,
                categories: categoriesSnapshot,
                recurringSeries: recurringSnapshot,
                accounts: accountsSnapshot,
                preAggregated: preAggregated
            )

            let totalDur = totalStart.duration(to: .now)
            let totalMs = Int(totalDur.components.seconds * 1000) + Int(totalDur.components.attoseconds / 1_000_000_000_000_000)

            // Hop back to MainActor for the final UI write.
            // Use self.currentGranularity (not the captured `priorityGranularity`) so that if the
            // user switched granularity while the background task was running, we show the right data.
            let finalInsights = newInsights
            let finalPoints   = newPoints
            let finalTotals   = newTotals
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.precomputedInsights     = finalInsights
                self.precomputedPeriodPoints = finalPoints
                self.precomputedTotals       = finalTotals
                self.healthScore             = computedHealthScore
                self.applyPrecomputed(for: self.currentGranularity)
                Self.logger.debug("🔧 [InsightsVM] Background recompute END — total \(totalMs)ms — UI updated for .\(self.currentGranularity.rawValue, privacy: .public)")
            }
        }
    }

    /// Applies precomputed data for the given granularity to observable properties.
    ///
    /// `withTransaction(animation: nil)` suppresses implicit animations for all callers:
    ///   - `currentGranularity.didSet` (granularity switch cache HIT)
    ///   - `onAppear()` (back-navigation cache HIT)
    ///   - `loadInsightsBackground()` MainActor writes
    ///
    /// Views with explicit `.animation(_:value:)` modifiers (e.g. ContentRevealModifier's
    /// opacity transition) override this transaction for their specific tracked value — their
    /// animations fire normally. Only background implicit transitions are suppressed.
    private func applyPrecomputed(for granularity: InsightGranularity) {
        withTransaction(SwiftUI.Transaction(animation: nil)) {
            insights         = precomputedInsights[granularity] ?? []
            periodDataPoints = precomputedPeriodPoints[granularity] ?? []
            let totals       = precomputedTotals[granularity]
            totalIncome      = totals?.income   ?? 0
            totalExpenses    = totals?.expenses ?? 0
            netFlow          = totals?.netFlow  ?? 0
            currentBucketIncome   = totals?.currentBucketIncome   ?? 0
            currentBucketExpenses = totals?.currentBucketExpenses ?? 0
            currentBucketNetFlow  = totals?.currentBucketNetFlow  ?? 0
            previousBucketIncome   = totals?.previousBucketIncome   ?? 0
            previousBucketExpenses = totals?.previousBucketExpenses ?? 0
            previousBucketNetFlow  = totals?.previousBucketNetFlow  ?? 0
            currentBucketLabel = granularity.currentBucketLabel()
            isLoading        = false
        }
    }

    /// Returns the totals for the period point whose `key` matches.
    /// Key-based lookup is robust across all granularities (including `.allTime`
    /// whose key is "all" with `periodStart = .distantPast` — date filtering would
    /// miss it). Same convention used elsewhere via `granularity.currentPeriodKey`.
    private nonisolated static func bucketTotals(
        in points: [PeriodDataPoint],
        forKey key: String
    ) -> (income: Double, expenses: Double) {
        guard let p = points.first(where: { $0.key == key }) else { return (0, 0) }
        return (p.income, p.expenses)
    }

    /// Captures a snapshot of account balances on MainActor for safe use on background thread.
    private func makeBalanceSnapshot() -> [String: Double] {
        var snapshot = [String: Double]()
        snapshot.reserveCapacity(transactionStore.accounts.count)
        for account in transactionStore.accounts {
            snapshot[account.id] = transactionsViewModel.calculateTransactionsBalance(for: account.id)
        }
        return snapshot
    }

    // MARK: - Legacy loadInsights

    /// Backward-compatible bridge: converts TimeFilter preset to InsightGranularity.
    func loadInsights(timeFilter: TimeFilter) {
        currentTimeFilter = timeFilter
        switch timeFilter.preset {
        case .today, .yesterday, .thisWeek, .last30Days:
            switchGranularity(.week)
        case .thisMonth, .lastMonth:
            switchGranularity(.month)
        case .thisYear, .lastYear:
            switchGranularity(.year)
        case .allTime, .custom:
            switchGranularity(.month)
        }
    }

    func refreshInsights(timeFilter: TimeFilter) {
        currentTimeFilter = timeFilter
        refreshInsights()
    }
}
