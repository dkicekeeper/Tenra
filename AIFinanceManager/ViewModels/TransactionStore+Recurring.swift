//
//  TransactionStore+Recurring.swift
//  AIFinanceManager
//
//  Created on 2026-02-09
//  Phase 9: Aggressive Integration - Recurring Operations
//
//  Purpose: Extension for recurring transaction operations in TransactionStore
//  All recurring CRUD operations are now part of TransactionStore (Single Source of Truth)
//

import Foundation

// MARK: - Recurring CRUD Operations

extension TransactionStore {
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

    /// Create a new recurring series
    /// Automatically generates transactions for the specified horizon
    /// - Parameter series: The recurring series to create
    /// - Throws: TransactionStoreError if validation fails
    func createSeries(_ series: RecurringSeries) async throws {
        // 1. Validate series
        try validateSeries(series)

        // 2. Create event (this adds series to recurringSeries array)
        let event = TransactionEvent.seriesCreated(series)
        try await apply(event)

        // 3. Generate and add initial transactions
        try await generateAndAddTransactions(for: series, horizonMonths: 3)

        // 5. Schedule notifications if subscription
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

    /// Update an existing recurring series
    /// Regenerates future transactions if parameters changed
    /// - Parameter series: The updated recurring series
    /// - Throws: TransactionStoreError if series not found or validation fails
    func updateSeries(_ series: RecurringSeries) async throws {
        // 1. Find existing series
        guard let old = recurringSeries.first(where: { $0.id == series.id }) else {
            throw TransactionStoreError.seriesNotFound
        }

        // 2. Validate
        try validateSeries(series)

        // 3. Create event
        let event = TransactionEvent.seriesUpdated(old: old, new: series)

        // 4. Apply
        try await apply(event)

        // 5. Update notifications if subscription
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

    /// Stop a recurring series (no more future transactions)
    /// - Parameters:
    ///   - seriesId: The ID of the series to stop
    ///   - fromDate: Date from which to stop (future transactions after this date will be deleted)
    /// - Throws: TransactionStoreError if series not found
    func stopSeries(id seriesId: String, fromDate: String) async throws {
        // 1. Validate series exists
        guard recurringSeries.contains(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        // 2. Create event
        let event = TransactionEvent.seriesStopped(seriesId: seriesId, fromDate: fromDate)

        // 3. Apply
        try await apply(event)

        // 4. Cancel notifications
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

        // 2. Create event
        let event = TransactionEvent.seriesDeleted(seriesId: seriesId, deleteTransactions: deleteTransactions)

        // 3. Apply
        try await apply(event)

        // 4. Cancel notifications
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
        guard let series = recurringSeries.first(where: { $0.id == seriesId }) else {
            return []
        }

        // 3. Generate transactions using correct API
        let existingTransactionIds = Set(transactions.map { $0.id })
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
        guard let series = recurringSeries.first(where: { $0.id == seriesId }) else {
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
        let existingTransactionIds = Set(transactions.map { $0.id })

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

    /// Invalidate cache for a specific series
    /// Call this when series is updated to ensure fresh data
    /// - Parameter seriesId: The series ID to invalidate
    func invalidateCache(for seriesId: String) {
        // Phase 03-PERF-02: delegate to RecurringStore
        recurringStore.invalidateCacheFor(seriesId: seriesId)
    }

    /// Pause a subscription (subscription-specific convenience method)
    /// - Parameter seriesId: The subscription ID to pause
    /// - Throws: TransactionStoreError if series not found or not a subscription
    func pauseSubscription(id seriesId: String) async throws {
        // 1. Find series
        guard let series = recurringSeries.first(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        guard series.isSubscription else {
            throw TransactionStoreError.invalidSeriesData
        }

        // 2. Update with paused status
        var updated = series
        updated.status = .paused

        try await updateSeries(updated)

    }

    /// Resume a subscription (subscription-specific convenience method)
    /// - Parameter seriesId: The subscription ID to resume
    /// - Throws: TransactionStoreError if series not found or not a subscription
    func resumeSubscription(id seriesId: String) async throws {
        // 1. Find series
        guard let series = recurringSeries.first(where: { $0.id == seriesId }) else {
            throw TransactionStoreError.seriesNotFound
        }

        guard series.isSubscription else {
            throw TransactionStoreError.invalidSeriesData
        }

        // 2. Update with active status
        var updated = series
        updated.status = .active

        try await updateSeries(updated)

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
}
