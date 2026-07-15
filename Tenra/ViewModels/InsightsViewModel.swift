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
    /// Non-nil means a full recompute is in flight (every granularity will be populated).
    @ObservationIgnored private var recomputeTask: Task<Void, Never>?

    /// Monotonic token identifying the current recompute. MainActor writes from a detached
    /// task only land if their captured generation still matches — so a superseded/cancelled
    /// task can never clobber the cache with stale data.
    @ObservationIgnored private var computeGeneration = 0

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
    var selectedFilter: InsightFilter = .all
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
    /// Total spendable balance across all accounts included in the Finances total
    /// (non-loan, `includeInBalance`). Period-independent — mirrors the home total.
    /// Recomputed on each background recompute from the balance snapshot.
    private(set) var availableBalance: Double = 0
    /// Latest computed available balance, applied to the published `availableBalance`
    /// from `applyPrecomputed` so its numeric-roll animation fires at reveal time
    /// alongside the bucket totals (setting it earlier rolled while still hidden).
    @ObservationIgnored private var pendingAvailableBalance: Double = 0
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
            } else if recomputeTask != nil {
                // A full recompute is already in flight — it computes EVERY granularity and
                // applies the current one on completion. Just show loading and wait. Starting a
                // new load here (the old behaviour) cancelled the in-flight phase 2 that
                // populates the other granularities, so rapid switching left the cache
                // perpetually incomplete and the cards lagged a step behind / showed all-time.
                self.isLoading = true
            } else {
                self.loadInsightsBackground()
            }
        }
    }

    /// Legacy: kept for CategoryDeepDive compatibility until it is migrated to granularity.
    private(set) var currentTimeFilter: TimeFilter = TimeFilter(preset: .allTime)

    // MARK: - Computed Properties

    var filteredInsights: [Insight] {
        switch selectedFilter {
        case .all:
            return insights
        case .urgent:
            // The dedicated filter is uncapped — a filter that silently hides
            // signals reads as a bug (the feed strip stays top-5).
            return allUrgentInsights
        case .category(let category):
            return insights.filter { $0.category == category }
        }
    }

    private func sortedBySeverity(_ items: [Insight]) -> [Insight] {
        items.sorted { $0.severity.sortOrder < $1.severity.sortOrder }
    }

    /// Every critical/warning insight across ALL categories, severity-sorted.
    /// Backs the «Важное» filter; the feed strip shows the top-5 slice.
    var allUrgentInsights: [Insight] {
        sortedBySeverity(insights.filter { $0.severity == .critical || $0.severity == .warning })
    }

    /// Cross-section signal strip "Важное сейчас" (audit 2026-07): the top
    /// critical/warning insights from ALL categories. Without it a critical
    /// budget signal sat below neutral spending stats — severity sorting only
    /// worked within sections.
    var urgentInsights: [Insight] {
        Array(allUrgentInsights.prefix(5))
    }

    /// Insights promoted to the urgent strip are excluded from their category
    /// sections — each card must appear once (matchedTransitionSource ids are
    /// unique per namespace) and duplicating them would lengthen the feed.
    private var urgentIds: Set<String> { Set(urgentInsights.map(\.id)) }

    private func sectionInsights(_ category: InsightCategory) -> [Insight] {
        sortedBySeverity(insights.filter { $0.category == category && !urgentIds.contains($0.id) })
    }

    var spendingInsights: [Insight]     { sectionInsights(.spending) }
    var incomeInsights: [Insight]       { sectionInsights(.income) }
    var budgetInsights: [Insight]       { sectionInsights(.budget) }
    var recurringInsights: [Insight]    { sectionInsights(.recurring) }
    var cashFlowInsights: [Insight]     { sectionInsights(.cashFlow) }
    var wealthInsights: [Insight]       { sectionInsights(.wealth) }
    var savingsInsights: [Insight]      { sectionInsights(.savings) }
    var forecastingInsights: [Insight]  { sectionInsights(.forecasting) }

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
        precomputedInsights = [:]
        precomputedPeriodPoints = [:]
        precomputedTotals = [:]
        recomputeTask?.cancel()
        debounceTask?.cancel()
        isStale = false
        loadInsightsBackground()
    }

    func selectFilter(_ filter: InsightFilter) {
        selectedFilter = filter
    }

    // MARK: - Category Deep Dive

    /// - Parameter periodKey: The period bucket to dive into. When `nil`, defaults to
    ///   the current period (non-paged breakdowns). The paged "Top categories"
    ///   breakdown passes the key of the page the user was viewing, so drilling into a
    ///   non-current month shows that month's data — not the current one.
    func categoryDeepDive(
        categoryName: String,
        periodKey: String? = nil
    ) -> (subcategories: [SubcategoryBreakdownItem], prevBucketTotal: Double) {
        // Use the selected granularity bucket only (not the full window).
        let currentKey   = periodKey ?? currentGranularity.currentPeriodKey
        let currentStart = currentGranularity.periodStart(for: currentKey)
        let currentEnd   = currentGranularity.periodEnd(for: currentKey)
        let currentFilter = TimeFilter(preset: .custom, startDate: currentStart, endDate: currentEnd)

        // Previous bucket — for the comparison card in InsightDeepDiveView.
        let prevKey   = currentGranularity.previousPeriodKey(before: currentKey)
        let prevStart = currentGranularity.periodStart(for: prevKey)
        let prevEnd   = currentStart   // prev bucket ends where current bucket begins
        let prevFilter = TimeFilter(preset: .custom, startDate: prevStart, endDate: prevEnd)

        // All transactions in memory — no window check needed.
        let allTransactions = Array(transactionStore.transactions)

        // Build txId → primary linked-subcategory name from the store indexes (MainActor).
        // The deep-dive groups by this because the add flow records subcategories only in
        // the link table, leaving the legacy `tx.subcategory` string nil.
        var subcategoryNameByTxId: [String: String] = [:]
        for tx in allTransactions where tx.category == categoryName {
            if let ids = transactionStore.subcategoryIdsByTransactionId[tx.id],
               let firstId = ids.first,
               let name = transactionStore.subcategoryById[firstId]?.name {
                subcategoryNameByTxId[tx.id] = name
            }
        }

        return insightsService.generateCategoryDeepDive(
            categoryName: categoryName,
            allTransactions: allTransactions,
            timeFilter: currentFilter,
            comparisonFilter: prevFilter,
            baseCurrency: baseCurrency,
            cacheManager: transactionsViewModel.cacheManager,
            currencyService: transactionsViewModel.currencyService,
            subcategoryNameByTxId: subcategoryNameByTxId
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
        computeGeneration &+= 1
        let myGen = computeGeneration

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
        // Total spendable balance (non-loan, included-in-balance accounts) — period-independent.
        // Stored as pending and published from applyPrecomputed so the numeric-roll animation
        // fires at reveal time alongside the bucket totals (not while still hidden by contentReveal).
        self.pendingAvailableBalance = accountsSnapshot
            .filter { !$0.isLoan && $0.includeInBalance }
            .reduce(0.0) { $0 + (balanceSnapshot[$1.id] ?? 0) }
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
                    // Only the current generation clears loading — a superseded task must not
                    // flip isLoading while a newer recompute is running.
                    guard let self, self.computeGeneration == myGen, self.isLoading else { return }
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

            // Health score needs only .month period data, which is fully derivable
            // from preAggregated — compute it NOW and publish with the phase-1 write.
            // It used to be computed after phase 2, so the badge popped in seconds
            // after the rest of the feed. When priority == .month we reuse the
            // phase-1 points; otherwise we build them via the SAME preAggregated
            // path phase 2 will use for .month (identical result, O(months) cost).
            let monthPointsForScore = newPoints[.month] ?? service.computePeriodDataPointsFromPreAggregated(
                preAggregated: preAggregated,
                granularity: .month,
                firstTransactionDate: preAggregated.firstDate
            )
            var monthIncome = 0.0; var monthExpenses = 0.0
            for p in monthPointsForScore { monthIncome += p.income; monthExpenses += p.expenses }
            let computedHealthScore = service.computeHealthScore(
                totalIncome: monthIncome,
                totalExpenses: monthExpenses,
                latestNetFlow: monthPointsForScore.last?.netFlow ?? 0,
                monthsInWindow: monthPointsForScore.count,
                baseCurrency: currency,
                balanceFor: { balanceSnapshot[$0] ?? 0 },
                allTransactions: allTransactions,
                categories: categoriesSnapshot,
                recurringSeries: recurringSnapshot,
                accounts: accountsSnapshot,
                preAggregated: preAggregated
            )

            // Show the current granularity immediately — user sees real data, not zeros
            let phase1Insights = newInsights
            let phase1Points   = newPoints
            let phase1Totals   = newTotals
            await MainActor.run { [weak self] in
                // Skip if this task was superseded — writing would clobber the newer task's cache.
                guard let self, self.computeGeneration == myGen else { return }
                // Merge, don't replace: replacing wiped the other granularities' precomputed
                // data until phase 2 finished, so switching granularity mid-flight showed
                // empty/stale cards. Merging keeps already-computed granularities available.
                self.precomputedInsights.merge(phase1Insights) { _, new in new }
                self.precomputedPeriodPoints.merge(phase1Points) { _, new in new }
                self.precomputedTotals.merge(phase1Totals) { _, new in new }
                self.healthScore = computedHealthScore
                self.applyPrecomputed(for: self.currentGranularity)
                Self.logger.debug("🔧 [InsightsVM] Priority gran done — .\(priorityGranularity.rawValue, privacy: .public) shown early (health score included)")
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

            let totalDur = totalStart.duration(to: .now)
            let totalMs = Int(totalDur.components.seconds * 1000) + Int(totalDur.components.attoseconds / 1_000_000_000_000_000)

            // Hop back to MainActor for the final UI write.
            // Use self.currentGranularity (not the captured `priorityGranularity`) so that if the
            // user switched granularity while the background task was running, we show the right data.
            let finalInsights = newInsights
            let finalPoints   = newPoints
            let finalTotals   = newTotals
            await MainActor.run { [weak self] in
                guard let self, self.computeGeneration == myGen else { return }
                self.precomputedInsights.merge(finalInsights) { _, new in new }
                self.precomputedPeriodPoints.merge(finalPoints) { _, new in new }
                self.precomputedTotals.merge(finalTotals) { _, new in new }
                // (healthScore published in the phase-1 write — needs only .month data)
                // All granularities are now cached — mark the recompute finished so subsequent
                // granularity switches read the cache synchronously instead of waiting.
                self.recomputeTask = nil
                self.applyPrecomputed(for: self.currentGranularity)
                Self.logger.debug("🔧 [InsightsVM] Background recompute END — total \(totalMs)ms — UI updated for .\(self.currentGranularity.rawValue, privacy: .public)")

                // Insight signal notifications (audit 2026-07): diff the fresh .month
                // insights against the alert history — new critical/warning signals
                // fire a local push (7-day dedup + 5/week cap in InsightSignalService).
                if let monthInsights = finalInsights[.month] {
                    Task { await InsightSignalService.shared.processInsights(monthInsights) }
                }
                // Weekly digest (Phase D): refresh the Monday-09:00 push content
                // from the freshly computed week buckets.
                if let weekPoints = finalPoints[.week] {
                    let digestCurrency = self.baseCurrency
                    Task { await WeeklyDigestScheduler.shared.reschedule(weekPoints: weekPoints, baseCurrency: digestCurrency) }
                }
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
        // Don't apply a granularity that isn't computed yet — that would flash empty cards
        // (or leave the previous granularity's data in place). Keep showing loading; the
        // in-flight recompute re-applies the current granularity when it lands.
        guard let granInsights = precomputedInsights[granularity] else {
            isLoading = true
            return
        }
        withTransaction(SwiftUI.Transaction(animation: nil)) {
            insights         = granInsights
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
            availableBalance   = pendingAvailableBalance
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
