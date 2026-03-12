//
//  RecurringTransactionGenerator.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: TransactionsViewModel Decomposition
//

import Foundation

/// Service responsible for generating recurring transactions
/// Extracted from TransactionsViewModel to improve separation of concerns
nonisolated class RecurringTransactionGenerator {

    // MARK: - Properties

    private let dateFormatter: DateFormatter
    private let calendar: Calendar

    // MARK: - Initialization

    init(dateFormatter: DateFormatter, calendar: Calendar = .current) {
        self.dateFormatter = dateFormatter
        self.calendar = calendar
    }

    // MARK: - Transaction Generation

    /// Generate transactions for all active recurring series
    /// - Parameters:
    ///   - series: Array of recurring series
    ///   - existingOccurrences: Array of existing occurrences to avoid duplicates
    ///   - existingTransactionIds: Set of existing transaction IDs
    ///   - accounts: Array of accounts for resolving account names
    ///   - baseCurrency: Base currency for conversion
    ///   - horizonMonths: Number of months to generate ahead (default: 3)
    /// - Returns: Tuple of (new transactions, new occurrences)
    func generateTransactions(
        series: [RecurringSeries],
        existingOccurrences: [RecurringOccurrence],
        existingTransactionIds: Set<String>,
        accounts: [Account],
        baseCurrency: String,
        horizonMonths: Int = 3
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        let today = calendar.startOfDay(for: Date())
        guard let horizonDate = calendar.date(byAdding: .month, value: horizonMonths, to: today) else {
            return ([], [])
        }

        // Build set of existing occurrence keys
        var existingOccurrenceKeys: Set<String> = []
        for occurrence in existingOccurrences {
            existingOccurrenceKeys.insert("\(occurrence.seriesId):\(occurrence.occurrenceDate)")
        }

        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []

        // Generate for each active series
        for activeSeries in series where activeSeries.isActive {
            let (transactions, occurrences) = generateTransactionsForSeries(
                series: activeSeries,
                horizonDate: horizonDate,
                existingOccurrenceKeys: &existingOccurrenceKeys,
                existingTransactionIds: existingTransactionIds,
                accounts: accounts,
                baseCurrency: baseCurrency
            )

            newTransactions.append(contentsOf: transactions)
            newOccurrences.append(contentsOf: occurrences)
        }

        return (newTransactions, newOccurrences)
    }

    /// Generate transactions for a single recurring series
    /// - Parameters:
    ///   - series: The recurring series
    ///   - horizonDate: The date to generate up to
    ///   - existingOccurrenceKeys: Set of existing occurrence keys (modified in place)
    ///   - existingTransactionIds: Set of existing transaction IDs
    ///   - accounts: Array of accounts for resolving account names
    ///   - baseCurrency: Base currency for conversion
    /// - Returns: Tuple of (transactions, occurrences) for this series
    private func generateTransactionsForSeries(
        series: RecurringSeries,
        horizonDate: Date,
        existingOccurrenceKeys: inout Set<String>,
        existingTransactionIds: Set<String>,
        accounts: [Account],
        baseCurrency: String
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        guard let startDate = dateFormatter.date(from: series.startDate) else {
            return ([], [])
        }

        // Calculate reasonable maxIterations based on frequency
        let maxIterations = calculateMaxIterations(
            series: series,
            startDate: startDate,
            horizonDate: horizonDate
        )

        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []
        var currentDate = startDate
        var iterationCount = 0

        while currentDate <= horizonDate && iterationCount < maxIterations {
            iterationCount += 1

            let dateString = dateFormatter.string(from: currentDate)
            let occurrenceKey = "\(series.id):\(dateString)"

            // Check if occurrence already exists
            if !existingOccurrenceKeys.contains(occurrenceKey) {
                let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue
                let transactionDate = dateFormatter.date(from: dateString) ?? Date()
                let createdAt = transactionDate.timeIntervalSince1970

                let transactionId = TransactionIDGenerator.generateID(
                    date: dateString,
                    description: series.description,
                    amount: amountDouble,
                    type: .expense,
                    currency: series.currency,
                    createdAt: createdAt
                )

                // Check if transaction already exists
                if !existingTransactionIds.contains(transactionId) {
                    let occurrenceId = UUID().uuidString

                    // Resolve account names
                    let accountName = series.accountId.flatMap { accountId in
                        accounts.first(where: { $0.id == accountId })?.name
                    }
                    let targetAccountName = series.targetAccountId.flatMap { targetAccountId in
                        accounts.first(where: { $0.id == targetAccountId })?.name
                    }

                    // Calculate target currency and amount for display
                    var targetCurrency: String? = nil
                    var targetAmount: Double? = nil

                    // If subscription currency differs from base currency, show equivalent
                    if series.currency != baseCurrency {
                        // Use sync conversion (from cache)
                        if let convertedValue = CurrencyConverter.convertSync(
                            amount: amountDouble,
                            from: series.currency,
                            to: baseCurrency
                        ) {
                            targetCurrency = baseCurrency
                            targetAmount = convertedValue
                        }
                    }

                    let transaction = Transaction(
                        id: transactionId,
                        date: dateString,
                        description: series.description,
                        amount: amountDouble,
                        currency: series.currency,
                        convertedAmount: nil,
                        type: .expense,
                        category: series.category,
                        subcategory: series.subcategory,
                        accountId: series.accountId,
                        targetAccountId: series.targetAccountId,
                        accountName: accountName,
                        targetAccountName: targetAccountName,
                        targetCurrency: targetCurrency,
                        targetAmount: targetAmount,
                        recurringSeriesId: series.id,
                        recurringOccurrenceId: occurrenceId,
                        createdAt: createdAt
                    )

                    let occurrence = RecurringOccurrence(
                        id: occurrenceId,
                        seriesId: series.id,
                        occurrenceDate: dateString,
                        transactionId: transactionId
                    )

                    newTransactions.append(transaction)
                    newOccurrences.append(occurrence)
                    existingOccurrenceKeys.insert(occurrenceKey)
                }
            }

            // Calculate next date based on frequency
            guard let nextDate = calculateNextDate(from: currentDate, frequency: series.frequency) else {
                break
            }

            // Safety check: ensure we're moving forward in time
            if nextDate <= currentDate {
                break
            }

            currentDate = nextDate
        }

        return (newTransactions, newOccurrences)
    }

    // MARK: - Helper Methods

    /// Calculate maximum iterations based on frequency and date range
    private func calculateMaxIterations(
        series: RecurringSeries,
        startDate: Date,
        horizonDate: Date
    ) -> Int {
        let daysBetweenStartAndHorizon = calendar.dateComponents([.day], from: startDate, to: horizonDate).day ?? 0
        guard daysBetweenStartAndHorizon > 0 else { return 1 }

        switch series.frequency {
        case .daily:
            return min(daysBetweenStartAndHorizon + 10, 10000) // Max 10000 for safety
        case .weekly:
            return min((daysBetweenStartAndHorizon / 7) + 10, 2000)
        case .monthly:
            return min((daysBetweenStartAndHorizon / 30) + 10, 500)
        case .yearly:
            return min((daysBetweenStartAndHorizon / 365) + 10, 100)
        }
    }

    /// Calculate next date based on frequency
    private func calculateNextDate(from currentDate: Date, frequency: RecurringFrequency) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: currentDate)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: currentDate)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: currentDate)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: currentDate)
        }
    }

    // MARK: - Single Next Occurrence Generation

    /// Generates all missing past occurrences + exactly 1 future occurrence for a single series.
    ///
    /// Replaces the 3-month horizon approach. Works correctly for all frequencies:
    /// - `.daily`:   fills gaps day-by-day, then 1 tomorrow
    /// - `.weekly`:  fills weekly gaps, then 1 next week
    /// - `.monthly`: fills monthly gaps, then 1 next month
    /// - `.yearly`:  fills yearly gaps (rare), then 1 next year — horizon would miss this
    ///
    /// Algorithm:
    ///   1. Find `latestOccurrenceDate` for this series in `existingOccurrences`
    ///   2. `candidateDate` = latestOccurrenceDate + step  (or series.startDate if no occurrences)
    ///   3. While candidateDate <= today AND occurrence doesn't exist → generate (backfill)
    ///   4. Generate 1 more future occurrence (candidateDate > today) → STOP
    ///
    /// - Returns: new transactions + occurrences to add. Empty if series has no valid startDate
    ///            or already has a future transaction.
    func generateUpToNextFuture(
        series: RecurringSeries,
        existingOccurrences: [RecurringOccurrence],
        existingTransactionIds: Set<String>,
        accounts: [Account],
        baseCurrency: String
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        guard series.isActive else { return ([], []) }
        guard let startDate = dateFormatter.date(from: series.startDate) else { return ([], []) }

        let today = calendar.startOfDay(for: Date())

        // Build fast lookup for existing occurrences of THIS series
        var existingOccurrenceKeys: Set<String> = []
        for occ in existingOccurrences where occ.seriesId == series.id {
            existingOccurrenceKeys.insert("\(occ.seriesId):\(occ.occurrenceDate)")
        }

        // Find the latest occurrence date for this series → advance from there
        let latestOccurrenceDate: Date? = existingOccurrences
            .filter { $0.seriesId == series.id }
            .compactMap { dateFormatter.date(from: $0.occurrenceDate) }
            .max()

        // Determine starting candidate: right after the last known occurrence
        var candidateDate: Date
        if let latest = latestOccurrenceDate {
            guard let next = calculateNextDate(from: latest, frequency: series.frequency) else {
                return ([], [])
            }
            candidateDate = next
        } else {
            candidateDate = startDate
        }

        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []
        var iterationCount = 0
        let maxIterations = 3650 // Safety cap (10 years of daily)

        while iterationCount < maxIterations {
            iterationCount += 1

            let dateString = dateFormatter.string(from: candidateDate)
            let occurrenceKey = "\(series.id):\(dateString)"

            // Skip if this occurrence already exists (shouldn't happen, but defensive)
            if existingOccurrenceKeys.contains(occurrenceKey) {
                guard let next = calculateNextDate(from: candidateDate, frequency: series.frequency),
                      next > candidateDate else { break }
                candidateDate = next
                // If we've moved past today and skipped a future — it means future already exists
                if candidateDate > today { break }
                continue
            }

            // Build the transaction
            let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue
            let createdAt = candidateDate.timeIntervalSince1970

            let transactionId = TransactionIDGenerator.generateID(
                date: dateString,
                description: series.description,
                amount: amountDouble,
                type: .expense,
                currency: series.currency,
                createdAt: createdAt
            )

            if !existingTransactionIds.contains(transactionId) {
                let occurrenceId = UUID().uuidString

                let accountName = series.accountId.flatMap { id in
                    accounts.first(where: { $0.id == id })?.name
                }
                let targetAccountName = series.targetAccountId.flatMap { id in
                    accounts.first(where: { $0.id == id })?.name
                }

                var targetCurrency: String? = nil
                var targetAmount: Double? = nil
                if series.currency != baseCurrency {
                    if let converted = CurrencyConverter.convertSync(
                        amount: amountDouble,
                        from: series.currency,
                        to: baseCurrency
                    ) {
                        targetCurrency = baseCurrency
                        targetAmount = converted
                    }
                }

                let transaction = Transaction(
                    id: transactionId,
                    date: dateString,
                    description: series.description,
                    amount: amountDouble,
                    currency: series.currency,
                    convertedAmount: nil,
                    type: .expense,
                    category: series.category,
                    subcategory: series.subcategory,
                    accountId: series.accountId,
                    targetAccountId: series.targetAccountId,
                    accountName: accountName,
                    targetAccountName: targetAccountName,
                    targetCurrency: targetCurrency,
                    targetAmount: targetAmount,
                    recurringSeriesId: series.id,
                    recurringOccurrenceId: occurrenceId,
                    createdAt: createdAt
                )

                let occurrence = RecurringOccurrence(
                    id: occurrenceId,
                    seriesId: series.id,
                    occurrenceDate: dateString,
                    transactionId: transactionId
                )

                newTransactions.append(transaction)
                newOccurrences.append(occurrence)
                existingOccurrenceKeys.insert(occurrenceKey)
            }

            // If candidateDate is in the future — we just created the 1 future occurrence. Done.
            if candidateDate > today {
                break
            }

            // Advance to the next date
            guard let next = calculateNextDate(from: candidateDate, frequency: series.frequency),
                  next > candidateDate else { break }
            candidateDate = next
        }

        return (newTransactions, newOccurrences)
    }

    // MARK: - Future Transaction Cleanup

    /// Delete future transactions and occurrences for a series
    /// Used when regenerating transactions after series modification
    /// - Parameters:
    ///   - seriesId: The series ID
    ///   - transactions: Array of all transactions
    ///   - occurrences: Array of all occurrences
    /// - Returns: Tuple of (filtered transactions, filtered occurrences) with future items removed
    func deleteFutureTransactionsForSeries(
        seriesId: String,
        transactions: [Transaction],
        occurrences: [RecurringOccurrence]
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        let today = calendar.startOfDay(for: Date())

        // Filter out future transactions for this series
        let filteredTransactions = transactions.filter { transaction in
            guard transaction.recurringSeriesId == seriesId else { return true }
            guard let date = dateFormatter.date(from: transaction.date) else { return true }
            return date <= today
        }

        // Filter out future occurrences for this series
        let filteredOccurrences = occurrences.filter { occurrence in
            guard occurrence.seriesId == seriesId else { return true }
            guard let date = dateFormatter.date(from: occurrence.occurrenceDate) else { return true }
            return date <= today
        }

        return (filteredTransactions, filteredOccurrences)
    }

    // MARK: - Past Transaction Conversion

    /// Convert past recurring transactions to regular transactions
    /// This removes the recurring series ID from transactions that are in the past
    /// - Parameters:
    ///   - transactions: Array of transactions to process
    /// - Returns: Array of transactions with past recurring transactions converted to regular
    func convertPastRecurringToRegular(_ transactions: [Transaction]) -> [Transaction] {
        let today = calendar.startOfDay(for: Date())
        var result: [Transaction] = []

        for transaction in transactions {
            if let _ = transaction.recurringSeriesId,
               let transactionDate = dateFormatter.date(from: transaction.date),
               transactionDate <= today {
                // Convert to regular transaction
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: transaction.category,
                    subcategory: transaction.subcategory,
                    accountId: transaction.accountId,
                    targetAccountId: transaction.targetAccountId,
                    accountName: transaction.accountName,
                    targetAccountName: transaction.targetAccountName,
                    recurringSeriesId: nil, // Remove series ID
                    recurringOccurrenceId: nil, // Remove occurrence ID
                    createdAt: transaction.createdAt
                )
                result.append(updatedTransaction)
            } else {
                result.append(transaction)
            }
        }

        return result
    }
}
