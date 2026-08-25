//
//  BackgroundInsightsRefresher.swift
//  Tenra
//
//  Closes the BGAppRefresh follow-up from the 2026-07 insights audit: signals and
//  the weekly digest used to (re)compute only when the Analytics tab recomputed
//  insights. This task recomputes them headlessly a few times a day (iOS decides
//  exactly when — BGAppRefreshTask is best-effort), so signal pushes arrive while
//  the app is closed, at organic times via InsightSignalService.deliveryDates.
//
//  Deliberately headless: loads straight from CoreDataRepository — no
//  AppCoordinator, TransactionStore or ViewModels, so no UI side effects and no
//  MainActor startup cost. Known limitation (spec'd): the background pass does NOT
//  generate recurring catch-up or deposit interest — it sees data as of the last
//  foreground session. Acceptable for transition-style alerts.
//
//  Spec: docs/superpowers/specs/2026-08-25-background-insight-signals-design.md
//

import Foundation
import BackgroundTasks
import UserNotifications
import os

@MainActor
final class BackgroundInsightsRefresher {
    static let shared = BackgroundInsightsRefresher()

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    nonisolated static let taskIdentifier = "dakacom.Tenra.insightsRefresh"
    /// iOS treats this as "no earlier than"; actual runs are opportunistic.
    nonisolated static let refreshInterval: TimeInterval = 4 * 3600

    private static let logger = Logger(subsystem: "Tenra", category: "BackgroundInsightsRefresher")

    /// Register the launch handler. MUST be called before
    /// `didFinishLaunchingWithOptions` returns (BGTaskScheduler requirement).
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                Self.shared.handle(refreshTask)
            }
        }
    }

    /// Submit the next refresh request. Safe to call repeatedly — a new submit
    /// replaces the pending request for the same identifier.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected on Simulator (unsupported) and when Background App Refresh
            // is disabled in system settings — log, don't crash.
            Self.logger.debug("BG submit skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        // Chain the next run first, so a crash/expiration can't break the chain.
        scheduleNextRefresh()
        let work = Task { [weak self] in
            let success = await self?.refresh() ?? false
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Outcome of `loadAndCompute`: distinguishes "no data to act on" (a normal,
    /// successful no-op) from "cancelled mid-flight" (expiration cut work short).
    private enum LoadComputeOutcome {
        case empty
        case cancelled
        case computed(
            result: (results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])], sharedInsights: [Insight]),
            transactionsCount: Int
        )
    }

    /// Repository loads + InsightsService compute, entirely OFF the main actor and
    /// entirely STRUCTURED: `nonisolated` means the `await` from `refresh()` hops off
    /// MainActor right at the call boundary (no `Task.detached` needed), and the
    /// `async let` loads below are structured child tasks of the caller's `Task` — so
    /// `work.cancel()` in `handle(_:)` propagates all the way down into `Task.isCancelled`
    /// checks here, unlike the previous `Task.detached` usage which created unstructured
    /// top-level tasks that ignored cancellation and kept running past BG-task expiration.
    private nonisolated static func loadAndCompute(
        repository: CoreDataRepository,
        baseCurrency: String,
        service: InsightsService,
        cacheManager: TransactionCacheManager,
        // TransactionCurrencyService is a @MainActor class (project default isolation)
        // consumed here off-main — same accepted pattern as InsightsViewModel's detached
        // recompute; it's stateless, so this compiles and runs safely under
        // SWIFT_STRICT_CONCURRENCY = minimal.
        currencyService: TransactionCurrencyService
    ) async -> LoadComputeOutcome {
        async let transactionsLoad = repository.loadTransactions(dateRange: nil)
        async let accountsLoad = repository.loadAccounts()
        async let categoriesLoad = repository.loadCategories()
        async let seriesLoad = repository.loadRecurringSeries()
        let transactions = await transactionsLoad
        let accounts = await accountsLoad
        let categories = await categoriesLoad
        let series = await seriesLoad

        guard !transactions.isEmpty, !accounts.isEmpty else { return .empty }
        guard !Task.isCancelled else { return .cancelled }

        // Persisted balances (maintained by BalanceCoordinator.persistBalance while
        // the app runs) stand in for the in-memory balance snapshot.
        let balances = Dictionary(accounts.map { ($0.id, $0.balance) },
                                  uniquingKeysWith: { first, _ in first })
        let snapshot = InsightsService.DataSnapshot(
            transactions: transactions,
            categories: categories,
            recurringSeries: series,
            accounts: accounts,
            balanceFor: { balances[$0] ?? 0 }
        )

        let preAggregated = InsightsService.PreAggregatedData.build(
            from: transactions,
            baseCurrency: baseCurrency,
            recurringSeries: series
        )
        let result = service.computeGranularities(
            [.month, .week],
            transactions: transactions,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            snapshot: snapshot,
            firstTransactionDate: preAggregated.firstDate,
            preAggregated: preAggregated,
            sharedInsights: nil
        )
        guard !Task.isCancelled else { return .cancelled }
        return .computed(result: result, transactionsCount: transactions.count)
    }

    /// Headless recompute: repository load → InsightsService → signal pushes +
    /// weekly digest. Returns false only when work was cut short (cancellation).
    func refresh() async -> Bool {
        let settings = InsightSignalSettings.shared
        guard settings.isEnabled || settings.weeklyDigestEnabled else { return true }
        let auth = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional else { return true }

        // A failed load must NOT fall back to the default currency — that silently
        // computes and pushes amounts in the wrong currency for anyone whose base
        // currency isn't the default. Skip this pass instead; it's a no-op success,
        // not a failure, so the BG task isn't retried aggressively.
        guard let appSettings = try? await SettingsStorageService().loadSettings() else {
            Self.logger.warning("BG refresh: settings load failed — skipping pass")
            return true
        }
        let baseCurrency = appSettings.baseCurrency

        let repository = CoreDataRepository()
        let service = InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: nil)
        )
        let cacheManager = TransactionCacheManager()
        let currencyService = TransactionCurrencyService()

        let outcome = await Self.loadAndCompute(
            repository: repository,
            baseCurrency: baseCurrency,
            service: service,
            cacheManager: cacheManager,
            currencyService: currencyService
        )

        switch outcome {
        case .cancelled:
            return false
        case .empty:
            return true
        case .computed(let result, let transactionsCount):
            if let monthInsights = result.results[.month]?.insights {
                await InsightSignalService.shared.processInsights(monthInsights)
            }
            guard !Task.isCancelled else { return false }
            if let weekPoints = result.results[.week]?.periodPoints {
                await WeeklyDigestScheduler.shared.reschedule(
                    weekPoints: weekPoints,
                    baseCurrency: baseCurrency
                )
            }
            Self.logger.debug("BG refresh done: \(transactionsCount) tx, month insights: \(result.results[.month]?.insights.count ?? 0)")
            return true
        }
    }
}
