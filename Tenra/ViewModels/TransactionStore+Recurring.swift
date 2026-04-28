//
//  TransactionStore+Recurring.swift
//  Tenra
//
//  Created on 2026-02-09
//
//  Recurring transaction operations for TransactionStore.
//

import Foundation
import os

// MARK: - Recurring CRUD Operations

extension TransactionStore {
    private static let recurringLogger = Logger(subsystem: "Tenra", category: "TransactionStore.Recurring")

    /// Computed properties for recurring data

    /// Get all subscriptions (convenience)
    var subscriptions: [RecurringSeries] {
        recurringSeries.filter { $0.isSubscription }
    }

    /// Get active subscriptions (convenience)
    var activeSubscriptions: [RecurringSeries] {
        subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
    }

    // MARK: - Create Recurring Series

    /// Create a new recurring series.
    /// Generates all missing past occurrences (if startDate is historical) + exactly 1 future
    /// occurrence. This replaces the old 3-month horizon which failed for yearly frequency.
    /// - Parameter series: The recurring series to create
    /// - Throws: TransactionStoreError if validation fails
    func createSeries(_ series: RecurringSeries) async throws {
        // 1. Validate series
        try validateSeries(series)

        // 2. Create event (this adds series to recurringSeries array)
        let event = TransactionEvent.seriesCreated(series)
        try await apply(event)

        // 3. Generate initial transactions: past backfill + 1 future occurrence
        //    (no horizon cap — works correctly for all frequencies including .yearly)
        let existingTransactionIds = transactionIdSet
        let result = recurringGenerator.generateUpToNextFuture(
            series: series,
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: accounts,
            baseCurrency: baseCurrency
        )

        if !result.transactions.isEmpty {
            try await apply(TransactionEvent.bulkAdded(result.transactions))
            recurringStore.appendOccurrences(result.occurrences)
            recurringStore.saveOccurrences()
        }

        // 4. Schedule notifications if subscription
        if series.isSubscription, series.subscriptionStatus == .active {
            if let nextChargeDate = calculateNextChargeDate(for: series) {
                await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                    for: series,
                    nextChargeDate: nextChargeDate
                )
            }
        }
    }

    // MARK: - Update Recurring Series

    /// Update an existing recurring series.
    /// If frequency or startDate changed, deletes the existing future occurrence and
    /// regenerates a new one to reflect the updated schedule.
    /// - Parameter series: The updated recurring series
    /// - Throws: TransactionStoreError if series not found or validation fails
    func updateSeries(_ series: RecurringSeries) async throws {
        // 1. Find existing series
        guard let old = seriesById[series.id] else {
            throw TransactionStoreError.seriesNotFound
        }

        // 2. Validate
        try validateSeries(series)

        // 3. If frequency or startDate changed → delete future occurrence so it gets regenerated
        let scheduleChanged = old.frequency != series.frequency || old.startDate != series.startDate
        if scheduleChanged {
            let today = Calendar.current.startOfDay(for: Date())
            let futureTxs = transactions.filter { tx in
                guard tx.recurringSeriesId == series.id else { return false }
                guard let date = DateFormatters.dateFormatter.date(from: tx.date) else { return false }
                return date > today
            }
            for tx in futureTxs {
                try await apply(TransactionEvent.deleted(tx))
            }
            recurringStore.removeOccurrences(seriesId: series.id, afterDate: today)
        }

        // 4. Update series metadata
        let event = TransactionEvent.seriesUpdated(old: old, new: series)
        try await apply(event)

        // 5. If schedule changed (or no future tx exists) — generate the new next occurrence
        if scheduleChanged {
            let existingTransactionIds = transactionIdSet
            let result = recurringGenerator.generateUpToNextFuture(
                series: series,
                existingOccurrences: recurringOccurrences,
                existingTransactionIds: existingTransactionIds,
                accounts: accounts,
                baseCurrency: baseCurrency
            )
            if !result.transactions.isEmpty {
                try await apply(TransactionEvent.bulkAdded(result.transactions))
                recurringStore.appendOccurrences(result.occurrences)
                recurringStore.saveOccurrences()
            }
        }

        // 6. Update notifications if subscription
        if series.isSubscription {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: series.id)
            if series.subscriptionStatus == .active {
                if let nextChargeDate = calculateNextChargeDate(for: series) {
                    await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                        for: series,
                        nextChargeDate: nextChargeDate
                    )
                }
            }
        }
    }

    // MARK: - Stop Recurring Series

    /// Stop a recurring series (no more future transactions).
    /// Deletes all recurring transactions strictly after `fromDate`, then marks the series
    /// as inactive. Transactions on `fromDate` itself are kept (already executed).
    /// - Parameters:
    ///   - seriesId: The ID of the series to stop
    ///   - fromDate: Cutoff date string (inclusive); transactions AFTER this date are deleted
    /// - Throws: TransactionStoreError if series not found
    func stopSeries(id seriesId: String, fromDate: String) async throws {
        // 1. Validate series exists
        guard recurringSeries.contains(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        // 2. Delete future recurring transactions (strictly after fromDate).
        //    Each apply(.deleted) removes from self.transactions + CoreData atomically.
        let cutoff = DateFormatters.dateFormatter.date(from: fromDate) ?? Date()
        let futureTxs = transactions.filter { tx in
            guard tx.recurringSeriesId == seriesId else { return false }
            guard let txDate = DateFormatters.dateFormatter.date(from: tx.date) else { return false }
            return txDate > cutoff
        }
        for tx in futureTxs {
            try await apply(TransactionEvent.deleted(tx))
        }

        // 3. Prune future occurrences from in-memory store.
        //    persistIncremental(.seriesStopped) calls saveOccurrences() which persists the result.
        recurringStore.removeOccurrences(seriesId: seriesId, afterDate: cutoff)

        // 4. Mark series as stopped (isActive = false) + persist via saveSeries()
        let event = TransactionEvent.seriesStopped(seriesId: seriesId, fromDate: fromDate)
        try await apply(event)

        // 5. Cancel notifications
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
    }

    // MARK: - Delete Recurring Series

    /// Delete a recurring series
    /// - Parameters:
    ///   - seriesId: The ID of the series to delete
    ///   - deleteTransactions: If true, deletes all transactions; if false, converts to regular transactions
    /// - Throws: TransactionStoreError if series not found
    func deleteSeries(id seriesId: String, deleteTransactions: Bool = true) async throws {
        // 1. Validate series exists
        guard recurringSeries.contains(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        // 2. Handle transactions belonging to this series BEFORE deleting the series
        let seriesTransactions = transactions.filter { $0.recurringSeriesId == seriesId }
        if deleteTransactions {
            // Delete all transactions for this series (same pattern as stopSeries)
            for tx in seriesTransactions {
                try await apply(TransactionEvent.deleted(tx))
            }
        } else {
            // Convert recurring transactions to regular (detach from series)
            for tx in seriesTransactions {
                let converted = Transaction(
                    id: tx.id,
                    date: tx.date,
                    description: tx.description,
                    amount: tx.amount,
                    currency: tx.currency,
                    convertedAmount: tx.convertedAmount,
                    type: tx.type,
                    category: tx.category,
                    subcategory: tx.subcategory,
                    accountId: tx.accountId,
                    targetAccountId: tx.targetAccountId,
                    accountName: tx.accountName,
                    targetAccountName: tx.targetAccountName,
                    targetCurrency: tx.targetCurrency,
                    targetAmount: tx.targetAmount,
                    recurringSeriesId: nil,
                    recurringOccurrenceId: nil,
                    createdAt: tx.createdAt
                )
                try await apply(TransactionEvent.updated(old: tx, new: converted))
            }
        }

        // 3. Clean up occurrences for this series
        recurringStore.removeAllOccurrences(for: seriesId)

        // 4. Create event and apply (removes series from RecurringStore + persists)
        let event = TransactionEvent.seriesDeleted(seriesId: seriesId, deleteTransactions: deleteTransactions)
        try await apply(event)

        // 5. Cancel notifications
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
    }

    // MARK: - Private Validation

    /// Validate recurring series data
    private func validateSeries(_ series: RecurringSeries) throws {
        // Amount must be positive
        guard series.amount > 0 else {
            throw TransactionStoreError.invalidAmount
        }

        // Start date must be valid format
        let dateFormatter = DateFormatters.dateFormatter
        guard dateFormatter.date(from: series.startDate) != nil else {
            throw TransactionStoreError.invalidStartDate
        }

        // Account must exist (if specified)
        if let accountId = series.accountId, !accountId.isEmpty {
            guard accounts.contains(where: { $0.id == accountId }) else {
                throw TransactionStoreError.accountNotFound
            }
        }

        // Category must exist
        if !series.category.isEmpty {
            guard categories.contains(where: { $0.name == series.category }) else {
                throw TransactionStoreError.categoryNotFound
            }
        }
    }

    /// Calculate next charge date for a subscription
    private func calculateNextChargeDate(for series: RecurringSeries) -> Date? {
        return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
    }

    // MARK: - Query Operations (with LRU Cache)

    /// Get planned transactions for a recurring series
    /// Uses LRU cache for O(1) performance on cache hit
    /// - Parameters:
    ///   - seriesId: The ID of the recurring series
    ///   - horizon: Number of months to generate (default: 3)
    /// - Returns: Array of planned transactions
    func getPlannedTransactions(for seriesId: String, horizon: Int = 3) -> [Transaction] {
        // Create cache key
        let cacheKey = "\(seriesId)_\(horizon)"

        // 1. Try cache first (O(1))
        if let cached = recurringCache.get(cacheKey) {
            return cached
        }


        // 2. Cache miss: find series
        guard let series = seriesById[seriesId] else {
            return []
        }

        // 3. Generate transactions using correct API
        let existingTransactionIds = transactionIdSet
        let result = recurringGenerator.generateTransactions(
            series: [series],
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: accounts,
            baseCurrency: baseCurrency,
            horizonMonths: horizon
        )

        // 4. Cache result
        recurringCache.set(cacheKey, value: result.transactions)


        return result.transactions
    }

    /// Get next charge date for a subscription
    /// Uses cached computation for performance
    /// - Parameter seriesId: The subscription ID
    /// - Returns: Next charge date or nil if not found
    func nextChargeDate(for seriesId: String) -> Date? {
        guard let series = seriesById[seriesId] else {
            return nil
        }

        // Calculate next charge date
        return calculateNextChargeDate(for: series)
    }

    /// Generate all recurring transactions for the current horizon
    /// Used for initial data loading or manual refresh
    /// - Parameter horizon: Number of months to generate (default: 3)
    /// - Returns: Array of all generated transactions
    func generateAllRecurringTransactions(horizon: Int = 3) -> [Transaction] {
        let activeSeries = recurringSeries.filter { $0.isActive }
        let existingTransactionIds = transactionIdSet

        let result = recurringGenerator.generateTransactions(
            series: activeSeries,
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: accounts,
            baseCurrency: baseCurrency,
            horizonMonths: horizon
        )


        return result.transactions
    }

    // MARK: - Horizon Extension (Single Next Occurrence Model)

    /// Ensures every active series has exactly 1 future transaction.
    /// Called on app foreground and after full data load.
    ///
    /// For each active series:
    ///   - If a future transaction already exists → skip (invariant satisfied)
    ///   - Otherwise → generateUpToNextFuture: fills in missing past occurrences + creates 1 future
    func extendAllActiveSeriesHorizons() async {
        // Reentrancy guard: loadData() and applicationDidBecomeActive can both trigger this
        // concurrently on startup. Without the guard, two interleaving calls generate duplicate
        // transactions (each takes a snapshot before the other's apply() completes).
        guard !isExtendingHorizons else {
            Self.recurringLogger.debug("extendAllActiveSeriesHorizons: skipped — already running")
            return
        }
        isExtendingHorizons = true
        defer { isExtendingHorizons = false }

        let activeSeries = recurringSeries.filter { $0.isActive }
        guard !activeSeries.isEmpty else { return }

        let today = Calendar.current.startOfDay(for: Date())

        // Pre-compute the set of seriesIds that already have a future transaction.
        // Single O(N) scan over all transactions, then O(1) lookup per series — replaces
        // the previous O(N × M) pattern that scanned 19k transactions for every active
        // series and contributed to a multi-second MainActor block at startup.
        var seriesIdsWithFutureTx: Set<String> = []
        seriesIdsWithFutureTx.reserveCapacity(activeSeries.count)
        for tx in transactions {
            guard let seriesId = tx.recurringSeriesId else { continue }
            if seriesIdsWithFutureTx.contains(seriesId) { continue }
            guard let date = DateFormatters.dateFormatter.date(from: tx.date) else { continue }
            if date > today {
                seriesIdsWithFutureTx.insert(seriesId)
            }
        }

        for series in activeSeries {
            guard !seriesIdsWithFutureTx.contains(series.id) else { continue }

            // Generate backfill (past gaps) + 1 future
            let existingTransactionIds = transactionIdSet
            let result = recurringGenerator.generateUpToNextFuture(
                series: series,
                existingOccurrences: recurringOccurrences,
                existingTransactionIds: existingTransactionIds,
                accounts: accounts,
                baseCurrency: baseCurrency
            )

            guard !result.transactions.isEmpty else { continue }

            // Persist transactions
            let bulkEvent = TransactionEvent.bulkAdded(result.transactions)
            do {
                try await apply(bulkEvent)
            } catch {
                Self.recurringLogger.error("extendAllActiveSeriesHorizons: failed to apply bulk event for series \(series.id): \(error.localizedDescription)")
            }

            // Track occurrences
            recurringStore.appendOccurrences(result.occurrences)
            recurringStore.saveOccurrences()

            // Yield between series so the MainActor can interleave higher-priority UI
            // work (input handling, layout). Each apply() above already does heavy work;
            // without yielding, a many-series backlog freezes the UI for seconds at startup.
            await Task.yield()
        }
    }

    /// Invalidate cache for a specific series
    /// Call this when series is updated to ensure fresh data
    /// - Parameter seriesId: The series ID to invalidate
    func invalidateCache(for seriesId: String) {
        recurringStore.invalidateCacheFor(seriesId: seriesId)
    }

    /// Pause a subscription (subscription-specific convenience method)
    /// - Parameter seriesId: The subscription ID to pause
    /// - Throws: TransactionStoreError if series not found or not a subscription
    func pauseSubscription(id seriesId: String) async throws {
        // 1. Find series
        guard let series = seriesById[seriesId] else {
            throw TransactionStoreError.seriesNotFound
        }

        guard series.isSubscription else {
            throw TransactionStoreError.invalidSeriesData
        }

        // 2. Update with paused status — both isActive and status must be updated in tandem
        var updated = series
        updated.status = .paused
        updated.isActive = false

        try await updateSeries(updated)

        // Delete future transactions since series is now paused
        let today = Calendar.current.startOfDay(for: Date())
        let futureTxs = transactions.filter { tx in
            guard tx.recurringSeriesId == seriesId else { return false }
            guard let txDate = DateFormatters.dateFormatter.date(from: tx.date) else { return false }
            return txDate > today
        }
        for tx in futureTxs {
            try await apply(TransactionEvent.deleted(tx))
        }
    }

    /// Resume a subscription (subscription-specific convenience method)
    /// Delegates to resumeSeries after validating it is a subscription.
    /// - Parameter seriesId: The subscription ID to resume
    /// - Throws: TransactionStoreError if series not found or not a subscription
    func resumeSubscription(id seriesId: String) async throws {
        guard let series = seriesById[seriesId] else {
            throw TransactionStoreError.seriesNotFound
        }
        guard series.isSubscription else {
            throw TransactionStoreError.invalidSeriesData
        }
        try await resumeSeries(id: seriesId)
    }

    /// Resume any recurring series (subscriptions and generic recurring).
    /// Sets isActive = true (and status = .active for subscriptions), then generates
    /// the next future occurrence so the series is immediately visible again.
    /// - Parameter seriesId: The series ID to resume
    /// - Throws: TransactionStoreError if series not found
    func resumeSeries(id seriesId: String) async throws {
        // 1. Find existing series
        guard let series = seriesById[seriesId] else {
            throw TransactionStoreError.seriesNotFound
        }

        // 2. Build updated series with isActive = true
        var updated = series
        updated.isActive = true
        if updated.kind == .subscription {
            updated.status = .active
        }

        // 3. Persist the reactivation via updateSeries
        //    (scheduleChanged will be false → existing past txs are preserved)
        try await updateSeries(updated)

        // 4. Generate the next future occurrence
        //    updateSeries skips generation when only isActive/status changed,
        //    so we trigger it manually here.
        let existingTransactionIds = transactionIdSet
        let result = recurringGenerator.generateUpToNextFuture(
            series: updated,
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: accounts,
            baseCurrency: baseCurrency
        )
        if !result.transactions.isEmpty {
            try await apply(TransactionEvent.bulkAdded(result.transactions))
            recurringStore.appendOccurrences(result.occurrences)
            recurringStore.saveOccurrences()
        }

        // 5. Reschedule notifications if subscription
        if updated.isSubscription {
            if let nextChargeDate = calculateNextChargeDate(for: updated) {
                await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                    for: updated,
                    nextChargeDate: nextChargeDate
                )
            }
        }
    }

    /// Calculate total monthly cost of all active subscriptions in a target currency
    /// - Parameter targetCurrency: The currency to convert all amounts to
    /// - Returns: Tuple with total amount and list of individual conversions
    func calculateSubscriptionsTotalInCurrency(_ targetCurrency: String) async -> (total: Decimal, conversions: [(subscription: RecurringSeries, convertedAmount: Decimal)]) {
        var total: Decimal = 0
        var conversions: [(RecurringSeries, Decimal)] = []

        for subscription in activeSubscriptions {
            // Convert amount to target currency
            let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
            let convertedAmount = await CurrencyConverter.convert(
                amount: amount,
                from: subscription.currency,
                to: targetCurrency
            ) ?? amount

            let decimalAmount = Decimal(convertedAmount)
            total += decimalAmount
            conversions.append((subscription, decimalAmount))
        }

        return (total, conversions)
    }

    // MARK: - Link Existing Transactions to Subscription

    /// Link existing transactions to a subscription by setting their recurringSeriesId.
    /// Unlike loan linking, this does NOT change the transaction type or accountId —
    /// only the recurringSeriesId is set, making the transaction appear in the
    /// subscription's transaction history.
    func linkTransactionsToSubscription(
        seriesId: String,
        transactions: [Transaction]
    ) async throws {
        guard recurringSeries.contains(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        for tx in transactions.sorted(by: { $0.date < $1.date }) {
            let updated = Transaction(
                id: tx.id,
                date: tx.date,
                description: tx.description,
                amount: tx.amount,
                currency: tx.currency,
                convertedAmount: tx.convertedAmount,
                type: tx.type,
                category: tx.category,
                subcategory: tx.subcategory,
                accountId: tx.accountId,
                targetAccountId: tx.targetAccountId,
                accountName: tx.accountName,
                targetAccountName: tx.targetAccountName,
                targetCurrency: tx.targetCurrency,
                targetAmount: tx.targetAmount,
                recurringSeriesId: seriesId,
                recurringOccurrenceId: tx.recurringOccurrenceId,
                createdAt: tx.createdAt
            )
            // Use apply() directly — skips validate() which would reject
            // transactions whose category was renamed/deleted since creation.
            // Safe because we only change recurringSeriesId on existing transactions.
            try await apply(TransactionEvent.updated(old: tx, new: updated))
        }
    }

    /// Unlink all transactions currently linked to a subscription series.
    /// Clears `recurringSeriesId` (and `recurringOccurrenceId`) on each linked transaction.
    /// Bypasses `update()`'s recurring-guard by applying events directly.
    /// Returns the number of transactions that were unlinked.
    @discardableResult
    func unlinkAllTransactions(fromSeriesId seriesId: String) async throws -> Int {
        guard recurringSeries.contains(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        let linked = transactions.filter { $0.recurringSeriesId == seriesId }
        guard !linked.isEmpty else { return 0 }

        for tx in linked {
            let updated = Transaction(
                id: tx.id,
                date: tx.date,
                description: tx.description,
                amount: tx.amount,
                currency: tx.currency,
                convertedAmount: tx.convertedAmount,
                type: tx.type,
                category: tx.category,
                subcategory: tx.subcategory,
                accountId: tx.accountId,
                targetAccountId: tx.targetAccountId,
                accountName: tx.accountName,
                targetAccountName: tx.targetAccountName,
                targetCurrency: tx.targetCurrency,
                targetAmount: tx.targetAmount,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: tx.createdAt
            )
            try await apply(TransactionEvent.updated(old: tx, new: updated))
        }
        return linked.count
    }
}
