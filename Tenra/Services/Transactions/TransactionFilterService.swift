//
//  TransactionFilterService.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: TransactionsViewModel Decomposition
//

import Foundation

/// Service responsible for filtering transactions by various criteria
/// Extracted from TransactionsViewModel to improve separation of concerns
nonisolated class TransactionFilterService {

    // MARK: - Properties

    private let dateFormatter: DateFormatter

    // MARK: - Initialization

    init(dateFormatter: DateFormatter) {
        self.dateFormatter = dateFormatter
    }

    // MARK: - Time Range Filtering

    /// Filter transactions by time range
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - start: Start date of the range (inclusive)
    ///   - end: End date of the range (exclusive)
    /// - Returns: Filtered transactions within the time range
    func filterByTimeRange(
        _ transactions: [Transaction],
        start: Date,
        end: Date
    ) -> [Transaction] {
        return transactions.filter { transaction in
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= start && transactionDate < end
        }
    }

    /// Filter transactions that occurred on or before a specific date
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - date: The cutoff date (inclusive)
    /// - Returns: Filtered transactions
    func filterUpToDate(
        _ transactions: [Transaction],
        date: Date
    ) -> [Transaction] {
        return transactions.filter { transaction in
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate <= date
        }
    }

    // MARK: - Category Filtering

    /// Filter transactions by categories
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - categories: Set of category names to include
    /// - Returns: Filtered transactions matching the categories
    func filterByCategories(
        _ transactions: [Transaction],
        categories: Set<String>
    ) -> [Transaction] {
        return transactions.filter { transaction in
            categories.contains(transaction.category)
        }
    }

    // MARK: - Account Filtering

    /// Filter transactions by account ID
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - accountId: The account ID to filter by
    /// - Returns: Filtered transactions for the specified account
    func filterByAccount(
        _ transactions: [Transaction],
        accountId: String
    ) -> [Transaction] {
        return transactions.filter { transaction in
            transaction.accountId == accountId || transaction.targetAccountId == accountId
        }
    }

    /// Filter transactions by multiple account IDs
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - accountIds: Set of account IDs to filter by
    /// - Returns: Filtered transactions for the specified accounts
    func filterByAccounts(
        _ transactions: [Transaction],
        accountIds: Set<String>
    ) -> [Transaction] {
        return transactions.filter { transaction in
            if let accountId = transaction.accountId, accountIds.contains(accountId) {
                return true
            }
            if let targetAccountId = transaction.targetAccountId, accountIds.contains(targetAccountId) {
                return true
            }
            return false
        }
    }

    // MARK: - Type Filtering

    /// Filter transactions by type
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - type: The transaction type to filter by
    /// - Returns: Filtered transactions of the specified type
    func filterByType(
        _ transactions: [Transaction],
        type: TransactionType
    ) -> [Transaction] {
        return transactions.filter { $0.type == type }
    }

    /// Filter transactions by multiple types
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - types: Set of transaction types to filter by
    /// - Returns: Filtered transactions matching the types
    func filterByTypes(
        _ transactions: [Transaction],
        types: Set<TransactionType>
    ) -> [Transaction] {
        return transactions.filter { types.contains($0.type) }
    }

    // MARK: - Recurring Filtering

    /// Separate transactions into recurring and regular transactions
    /// - Parameters:
    ///   - transactions: Array of transactions to separate
    /// - Returns: Tuple containing (recurring, regular) transactions
    func separateRecurringTransactions(
        _ transactions: [Transaction]
    ) -> (recurring: [Transaction], regular: [Transaction]) {
        var recurring: [Transaction] = []
        var regular: [Transaction] = []

        for transaction in transactions {
            if transaction.recurringSeriesId != nil {
                recurring.append(transaction)
            } else {
                regular.append(transaction)
            }
        }

        return (recurring, regular)
    }

    /// Filter transactions for active recurring series within time range
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - series: Array of recurring series
    ///   - start: Start date of the range
    ///   - end: End date of the range
    /// - Returns: Filtered recurring transactions within the time range
    func filterRecurringInRange(
        _ transactions: [Transaction],
        series: [RecurringSeries],
        start: Date,
        end: Date
    ) -> [Transaction] {
        // Group transactions by series ID
        var transactionsBySeries: [String: [Transaction]] = [:]
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                transactionsBySeries[seriesId, default: []].append(transaction)
            }
        }

        var result: [Transaction] = []

        // Filter by active series and time range
        for activeSeries in series where activeSeries.isActive {
            guard let seriesTransactions = transactionsBySeries[activeSeries.id] else {
                continue
            }

            let transactionsInRange = seriesTransactions.filter { transaction in
                guard let date = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return date >= start && date < end
            }

            result.append(contentsOf: transactionsInRange)
        }

        return result
    }

    // MARK: - Combined Filtering

    /// Filter transactions by time range and categories
    /// Handles recurring transactions specially
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - series: Array of recurring series
    ///   - start: Start date of the range
    ///   - end: End date of the range
    ///   - categories: Optional set of categories to filter by
    /// - Returns: Filtered transactions
    func filterByTimeAndCategory(
        _ transactions: [Transaction],
        series: [RecurringSeries],
        start: Date,
        end: Date,
        categories: Set<String>?
    ) -> [Transaction] {
        // Apply category filter if provided
        var filteredTransactions = transactions
        if let categories = categories {
            filteredTransactions = filterByCategories(filteredTransactions, categories: categories)
        }

        // Separate recurring and regular transactions
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]
        var regularTransactions: [Transaction] = []

        for transaction in filteredTransactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                    continue
                }
                if transactionDate >= start && transactionDate < end {
                    regularTransactions.append(transaction)
                }
            }
        }

        // Filter recurring transactions
        var recurringTransactions: [Transaction] = []
        for activeSeries in series where activeSeries.isActive {
            guard let seriesTransactions = recurringTransactionsBySeries[activeSeries.id] else {
                continue
            }

            let transactionsInRange = seriesTransactions.filter { transaction in
                guard let date = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return date >= start && date < end
            }

            recurringTransactions.append(contentsOf: transactionsInRange)
        }

        return recurringTransactions + regularTransactions
    }

    // MARK: - Search Filtering

    /// Filter transactions by search query (description or amount)
    /// - Parameters:
    ///   - transactions: Array of transactions to filter
    ///   - query: Search query string
    /// - Returns: Filtered transactions matching the query
    func filterBySearch(
        _ transactions: [Transaction],
        query: String
    ) -> [Transaction] {
        let lowercasedQuery = query.lowercased()

        return transactions.filter { transaction in
            // Search in description
            if transaction.description.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search in amount (formatted)
            let amountString = String(format: "%.2f", transaction.amount)
            if amountString.contains(lowercasedQuery) {
                return true
            }

            return false
        }
    }
}
