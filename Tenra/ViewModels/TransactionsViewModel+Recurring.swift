//
//  TransactionsViewModel+Recurring.swift
//  AIFinanceManager
//
//  Recurring transactions and subscriptions extracted from TransactionsViewModel.
//  Phase C: File split for maintainability.
//

import Foundation

// MARK: - Recurring Transactions (routed through TransactionStore)

extension TransactionsViewModel {

    func createRecurringSeries(
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String?,
        description: String,
        accountId: String?,
        targetAccountId: String?,
        frequency: RecurringFrequency,
        startDate: String
    ) -> RecurringSeries {
        let series = RecurringSeries(
            amount: amount,
            currency: currency,
            category: category,
            subcategory: subcategory,
            description: description,
            accountId: accountId,
            targetAccountId: targetAccountId,
            frequency: frequency,
            startDate: startDate
        )
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.createSeries(series)
        }
        return series
    }

    func updateRecurringSeries(_ series: RecurringSeries) {
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.updateSeries(series)
        }
    }

    func stopRecurringSeries(_ seriesId: String) {
        let today = DateFormatters.dateFormatter.string(from: Date())
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.stopSeries(id: seriesId, fromDate: today)
        }
    }

    func stopRecurringSeriesAndCleanup(seriesId: String, transactionDate: String) {
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.stopSeries(id: seriesId, fromDate: transactionDate)
        }
    }

    func resumeRecurringSeries(_ seriesId: String) {
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.resumeSeries(id: seriesId)
        }
    }

    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.deleteSeries(id: seriesId, deleteTransactions: deleteTransactions)
        }
    }

    func archiveSubscription(_ seriesId: String) {
        // Subscription archiving (pause) — route through TransactionStore
        Task { @MainActor [weak self] in
            try? await self?.transactionStore?.pauseSubscription(id: seriesId)
        }
    }

    func nextChargeDate(for subscriptionId: String) -> Date? {
        transactionStore?.nextChargeDate(for: subscriptionId)
    }

    func generateRecurringTransactions() {
        // No-op: recurring generation happens inside TransactionStore.createSeries/updateSeries.
        // Called from AppCoordinator.initialize() as a background task — TransactionStore
        // already loaded recurring data during loadData(); no explicit regeneration needed.
    }

    /// DEPRECATED — kept for call-site compatibility only. Does nothing.
    @available(*, deprecated, message: "Use TransactionStore recurring methods directly.")
    func updateRecurringTransaction(_ transactionId: String, updateAllFuture: Bool,
        newAmount: Decimal? = nil, newCategory: String? = nil, newSubcategory: String? = nil) {
        // No-op: superseded by TransactionStore.updateSeries()
    }

    // MARK: - Subscriptions

    var subscriptions: [RecurringSeries] {
        recurringSeries.filter { $0.isSubscription }
    }

    var activeSubscriptions: [RecurringSeries] {
        subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
    }
}
