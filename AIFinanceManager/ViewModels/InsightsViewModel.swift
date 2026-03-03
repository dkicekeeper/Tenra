//
//  InsightsViewModel.swift
//  AIFinanceManager
//
//  Phase 23: Insights Performance & UI fixes
//  - 23-A: All heavy computation offloaded to background thread via Task.detached
//  - Eliminated UI freezes on first tab open (loadInsightsForeground blocked MainActor)
//  - Single Array copy of transactions per cycle — not per granularity (P4 fix)
//  - makeBalanceSnapshot() captures balances on MainActor before background hop
//  - Only the final UI write hops back via await MainActor.run
//
//  Phase 41: Insights freeze + excessive-recompute fixes
//  - computeHealthScore no longer @MainActor — snapshots passed as params, runs in Task.detached
//  - invalidateAndRecompute() debounces recomputes by 800ms (debounceTask)
//  - loadInsightsBackground() cancels pending debounce and clears isStale immediately
//  - InsightsView.onChange(of: isStale) removed — debounce in VM handles mutations while tab open
//

import Foundation
import SwiftUI
import Observation
import os

@Observable
@MainActor
final class InsightsViewModel {
    // MARK: - Logger

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsViewModel")

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
    private struct PeriodTotals {
        let income: Double
        let expenses: Double
        let netFlow: Double
    }
    @ObservationIgnored private var precomputedTotals: [InsightGranularity: PeriodTotals] = [:]

    /// Background recompute task handle — cancelled and replaced on each data change.
    @ObservationIgnored private var recomputeTask: Task<Void, Never>?

    /// Phase 41: Debounce task — coalesces rapid mutation bursts into a single recompute.
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// Phase 42: isStale is now @ObservationIgnored — InsightsView no longer observes it
    /// (Phase 41 already removed the .onChange). Used only as internal guard in onAppear().
    @ObservationIgnored private(set) var isStale: Bool = true

    /// Phase 42: Tracks whether Insights tab is currently visible.
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
    /// Phase 24 — Financial Health Score (computed once per recompute cycle, using .month granularity data)
    private(set) var healthScore: FinancialHealthScore? = nil

    // MARK: - Granularity (replaces TimeFilter for Insights)

    /// Settable from View via @Bindable — didSet handles applyPrecomputed side-effect.
    var currentGranularity: InsightGranularity = .month {
        didSet {
            guard oldValue != self.currentGranularity else { return }
            Self.logger.debug("🧠 [InsightsVM] granularity → \(self.currentGranularity.rawValue, privacy: .public)")
            if precomputedInsights[self.currentGranularity] != nil {
                // Phase 42: Cache HIT — instant switch (0ms).
                // withTransaction(animation: nil) is inside applyPrecomputed — covers all call sites.
                self.applyPrecomputed(for: self.currentGranularity)
            } else {
                // Phase 42: Cache MISS — trigger lazy background compute for this granularity only
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

    var spendingInsights: [Insight]     { insights.filter { $0.category == .spending } }
    var incomeInsights: [Insight]       { insights.filter { $0.category == .income } }
    var budgetInsights: [Insight]       { insights.filter { $0.category == .budget } }
    var recurringInsights: [Insight]    { insights.filter { $0.category == .recurring } }
    var cashFlowInsights: [Insight]     { insights.filter { $0.category == .cashFlow } }
    var wealthInsights: [Insight]       { insights.filter { $0.category == .wealth } }
    var savingsInsights: [Insight]      { insights.filter { $0.category == .savings } }     // Phase 24
    var forecastingInsights: [Insight]  { insights.filter { $0.category == .forecasting } } // Phase 24

    /// Phase 36: Read directly from TransactionStore (one hop instead of two)
    var baseCurrency: String {
        transactionStore.baseCurrency
    }

    var hasData: Bool {
        !transactionStore.transactions.isEmpty
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
    /// didSet on currentGranularity handles applyPrecomputed; kept for legacy call sites.
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

    /// Phase 42: Called when Insights tab disappears.
    func onDisappear() {
        isVisible = false
    }

    /// Phase 42: Lazy invalidation — marks stale and wipes caches.
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

        // Phase 42: Only schedule background compute when tab is visible
        guard isVisible else { return }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loadInsightsBackground()
            }
        }
    }

    func invalidateCache() {
        invalidateAndRecompute()
    }

    /// Phase 42: Fixed double-fire — invalidateAndRecompute() was scheduling a debounced
    /// loadInsightsBackground(), and then loadInsightsBackground() was called immediately too.
    /// Now: wipe caches directly and trigger immediate (non-debounced) background load.
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
        // Phase 31: Use current granularity bucket only (not the full window).
        let currentKey   = currentGranularity.currentPeriodKey
        let currentStart = currentGranularity.periodStart(for: currentKey)
        let currentEnd   = currentGranularity.periodEnd(for: currentKey)
        let currentFilter = TimeFilter(preset: .custom, startDate: currentStart, endDate: currentEnd)

        // Previous bucket — for the comparison card in CategoryDeepDiveView.
        let prevKey   = currentGranularity.previousPeriodKey
        let prevStart = currentGranularity.periodStart(for: prevKey)
        let prevEnd   = currentStart   // prev bucket ends where current bucket begins
        let prevFilter = TimeFilter(preset: .custom, startDate: prevStart, endDate: prevEnd)

        // Phase 40: All transactions in memory — window check removed.
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

    /// Phase 26: Two-phase progressive loading.
    /// Phase 1 — computes only the current (priority) granularity and writes to UI immediately.
    ///            User sees real data after ~1/5 of total computation time instead of zeros.
    /// Phase 2 — computes the remaining 4 granularities + health score, then does a final UI update.
    private func loadInsightsBackground() {
        // Phase 41: Guard against startup race — if transactions haven't landed on the
        // main actor yet (loadData() is still in flight), skip and stay stale so that
        // AppCoordinator's post-init invalidateAndRecompute() will trigger correctly.
        guard !transactionStore.transactions.isEmpty else { return }
        isStale = false          // Phase 41: clear stale flag immediately
        debounceTask?.cancel()   // Phase 41: cancel any pending debounce — we're computing now
        isLoading = true
        recomputeTask?.cancel()

        // Capture everything needed on the background thread while on MainActor
        let currency = baseCurrency
        let cacheManager = transactionsViewModel.cacheManager
        let currencyService = transactionsViewModel.currencyService
        let service = insightsService
        let allTransactions = Array(transactionStore.transactions)
        let balanceSnapshot = makeBalanceSnapshot()
        // Phase 41: Pre-capture @MainActor model snapshots so computeHealthScore
        // can run off the main thread (no @MainActor hop required).
        let categoriesSnapshot  = Array(transactionStore.categories)
        let recurringSnapshot   = Array(transactionStore.recurringSeries)
        let accountsSnapshot    = Array(transactionStore.accounts)
        let priorityGranularity = currentGranularity  // show this one first
        // Phase 42: firstDate scan moved OFF MainActor — PreAggregatedData.build() computes it
        // as part of its single O(N) pass on the background thread. No more 20-50ms MainActor block.

        recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let totalStart = ContinuousClock.now
            Self.logger.debug("🔧 [InsightsVM] Background recompute START (detached)")

            // Phase 42: Build PreAggregatedData once — single O(N) pass replaces ~10× O(N) scans per granularity.
            // This also computes firstDate, eliminating the previous MainActor O(N) date-parse scan.
            let preAggStart = ContinuousClock.now
            let preAggregated = InsightsService.PreAggregatedData.build(from: allTransactions, baseCurrency: currency)
            let preAggDur = preAggStart.duration(to: .now)
            let preAggMs = Int(preAggDur.components.seconds * 1000) + Int(preAggDur.components.attoseconds / 1_000_000_000_000_000)
            Self.logger.debug("⏱ [InsightsVM] PreAggregatedData.build(): \(preAggMs)ms")

            var newInsights = [InsightGranularity: [Insight]]()
            var newPoints   = [InsightGranularity: [PeriodDataPoint]]()
            var newTotals   = [InsightGranularity: PeriodTotals]()

            // ── Phase 1: priority granularity → early UI update ──────────────
            guard !Task.isCancelled else { return }

            let p1Start = ContinuousClock.now
            let phase1Result = await service.computeGranularities(
                [priorityGranularity],
                transactions: allTransactions,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: { balanceSnapshot[$0] ?? 0 },
                firstTransactionDate: preAggregated.firstDate,
                preAggregated: preAggregated,
                sharedInsights: nil     // Phase 42b: first call computes shared insights
            )
            let p1Dur = p1Start.duration(to: .now)
            let p1Ms = Int(p1Dur.components.seconds * 1000) + Int(p1Dur.components.attoseconds / 1_000_000_000_000_000)
            // Phase 42b: capture shared insights from first granularity for reuse in Phase 2
            let sharedInsights = phase1Result.sharedInsights

            for gran in [priorityGranularity] {
                guard let result = phase1Result.results[gran] else { continue }
                let pts = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in pts { income += p.income; expenses += p.expenses }
                newInsights[gran] = result.insights
                newPoints[gran]   = pts
                newTotals[gran]   = PeriodTotals(income: income, expenses: expenses, netFlow: income - expenses)
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(pts.count) pts")
            }
            Self.logger.debug("⏱ [InsightsVM] Phase 1 (.\(priorityGranularity.rawValue, privacy: .public)): \(p1Ms)ms — shared=\(sharedInsights.count)")

            guard !Task.isCancelled else { return }

            // Show the current granularity immediately — user sees real data, not zeros
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.precomputedInsights     = newInsights
                self.precomputedPeriodPoints = newPoints
                self.precomputedTotals       = newTotals
                self.applyPrecomputed(for: self.currentGranularity)
                Self.logger.debug("🔧 [InsightsVM] Phase 1 done — .\(priorityGranularity.rawValue, privacy: .public) shown early")
            }

            // ── Phase 2: remaining granularities ─────────────────────────────
            let remainingGrans = InsightGranularity.allCases.filter { $0 != priorityGranularity }
            guard !Task.isCancelled else { return }

            let p2Start = ContinuousClock.now
            let phase2Result = await service.computeGranularities(
                remainingGrans,
                transactions: allTransactions,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: { balanceSnapshot[$0] ?? 0 },
                firstTransactionDate: preAggregated.firstDate,
                preAggregated: preAggregated,
                sharedInsights: sharedInsights   // Phase 42b: reuse shared from Phase 1
            )
            let p2Dur = p2Start.duration(to: .now)
            let p2Ms = Int(p2Dur.components.seconds * 1000) + Int(p2Dur.components.attoseconds / 1_000_000_000_000_000)
            Self.logger.debug("⏱ [InsightsVM] Phase 2 (\(remainingGrans.count) grans): \(p2Ms)ms")

            for (gran, result) in phase2Result.results {
                let pts = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in pts { income += p.income; expenses += p.expenses }
                newInsights[gran] = result.insights
                newPoints[gran]   = pts
                newTotals[gran]   = PeriodTotals(income: income, expenses: expenses, netFlow: income - expenses)
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(pts.count) pts")
            }

            guard !Task.isCancelled else { return }

            // Health score uses .month data (available after phase 2 if priority wasn't .month,
            // or from phase 1 if priority was .month)
            let monthTotals   = newTotals[.month]
            let monthPoints   = newPoints[.month] ?? []
            let latestNetFlow = monthPoints.last?.netFlow ?? 0
            // Phase 41: No longer @MainActor — runs synchronously in Task.detached.
            // Phase 42: Pass preAggregated to avoid redundant O(N) scans inside computeHealthScore.
            let computedHealthScore = service.computeHealthScore(
                totalIncome: monthTotals?.income   ?? 0,
                totalExpenses: monthTotals?.expenses ?? 0,
                latestNetFlow: latestNetFlow,
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
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.precomputedInsights     = newInsights
                self.precomputedPeriodPoints = newPoints
                self.precomputedTotals       = newTotals
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
    ///   - `loadInsightsBackground()` Phase-1 and Phase-2 MainActor writes
    ///
    /// Views with explicit `.animation(_:value:)` modifiers (e.g. SkeletonLoadingModifier's
    /// spring transition) override this transaction for their specific tracked value — their
    /// animations fire normally. Only background implicit transitions are suppressed.
    private func applyPrecomputed(for granularity: InsightGranularity) {
        withTransaction(SwiftUI.Transaction(animation: nil)) {
            insights         = precomputedInsights[granularity] ?? []
            periodDataPoints = precomputedPeriodPoints[granularity] ?? []
            let totals       = precomputedTotals[granularity]
            totalIncome      = totals?.income   ?? 0
            totalExpenses    = totals?.expenses ?? 0
            netFlow          = totals?.netFlow  ?? 0
            isLoading        = false
        }
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
