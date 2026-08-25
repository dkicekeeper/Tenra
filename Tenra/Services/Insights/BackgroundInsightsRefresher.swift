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

    /// Headless recompute: repository load → InsightsService → signal pushes +
    /// weekly digest. Returns false only when work was cut short (cancellation).
    func refresh() async -> Bool {
        let settings = InsightSignalSettings.shared
        guard settings.isEnabled || settings.weeklyDigestEnabled else { return true }
        let auth = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional else { return true }

        let baseCurrency: String
        if let appSettings = try? await SettingsStorageService().loadSettings() {
            baseCurrency = appSettings.baseCurrency
        } else {
            baseCurrency = AppSettings.makeDefault().baseCurrency
        }

        // Repository fetches are nonisolated — run them off the main thread.
        let repository = CoreDataRepository()
        async let transactionsLoad = Task.detached(priority: .utility) {
            repository.loadTransactions(dateRange: nil)
        }.value
        async let accountsLoad = Task.detached(priority: .utility) {
            repository.loadAccounts()
        }.value
        async let categoriesLoad = Task.detached(priority: .utility) {
            repository.loadCategories()
        }.value
        async let seriesLoad = Task.detached(priority: .utility) {
            repository.loadRecurringSeries()
        }.value
        let transactions = await transactionsLoad
        let accounts = await accountsLoad
        let categories = await categoriesLoad
        let series = await seriesLoad

        guard !transactions.isEmpty, !accounts.isEmpty else { return true }
        guard !Task.isCancelled else { return false }

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
        let service = InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: nil)
        )
        let cacheManager = TransactionCacheManager()
        let currencyService = TransactionCurrencyService()

        let result = await Task.detached(priority: .utility) {
            let preAggregated = InsightsService.PreAggregatedData.build(
                from: transactions,
                baseCurrency: baseCurrency,
                recurringSeries: series
            )
            return service.computeGranularities(
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
        }.value
        guard !Task.isCancelled else { return false }

        if let monthInsights = result.results[.month]?.insights {
            await InsightSignalService.shared.processInsights(monthInsights)
        }
        if let weekPoints = result.results[.week]?.periodPoints {
            await WeeklyDigestScheduler.shared.reschedule(
                weekPoints: weekPoints,
                baseCurrency: baseCurrency
            )
        }
        Self.logger.debug("BG refresh done: \(transactions.count) tx, month insights: \(result.results[.month]?.insights.count ?? 0)")
        return true
    }
}
