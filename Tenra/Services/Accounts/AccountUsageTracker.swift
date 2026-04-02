//
//  AccountUsageTracker.swift
//  AIFinanceManager
//
//  Created on 2026-01-19
//

import Foundation

/// Tracks account usage statistics to provide smart default account selection
class AccountUsageTracker {

    // MARK: - Properties

    /// Transactions to analyze
    private let transactions: [Transaction]

    /// Accounts available in the system
    private let accounts: [Account]

    // MARK: - Initialization

    /// Initialize tracker with transactions and accounts
    /// - Parameters:
    ///   - transactions: All user transactions
    ///   - accounts: All available accounts
    init(transactions: [Transaction], accounts: [Account]) {
        self.transactions = transactions
        self.accounts = accounts
    }

    // MARK: - Smart Default Selection

    /// Get the smart default account based on usage statistics
    /// - Returns: The most appropriate account, or nil if no accounts exist
    ///
    /// Algorithm:
    /// - Usage Score (70%): Number of transactions for each account
    /// - Recency Score (30%): Recent transactions are weighted higher
    ///   - Last 24 hours: 100 points
    ///   - Last 7 days: 70 points
    ///   - Last 30 days: 40 points
    ///   - Older: 10 points
    func getSmartDefaultAccount() -> Account? {
        guard !accounts.isEmpty else { return nil }
        guard !transactions.isEmpty else { return accounts.first }

        // Calculate scores for each account
        var accountScores: [String: Double] = [:]

        // 1. Group transactions by accountId
        let accountUsage = Dictionary(grouping: transactions) { $0.accountId }

        // 2. Calculate score for each account
        for (accountId, accountTransactions) in accountUsage {
            guard let accountId = accountId else { continue }

            // Usage Score: count of transactions (70% weight)
            let usageScore = Double(accountTransactions.count) * 0.7

            // Recency Score: boost recent transactions (30% weight)
            let recencyScore = calculateRecencyScore(for: accountTransactions) * 0.3

            accountScores[accountId] = usageScore + recencyScore

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
                _ = accountId  // Debug log placeholder
            }
            #endif
        }

        // 3. Find account with highest score
        guard let topAccountId = accountScores.max(by: { $0.value < $1.value })?.key else {
            return accounts.first // Fallback
        }

        // 4. Return the account object
        let smartDefault = accounts.first { $0.id == topAccountId }

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs, let _ = smartDefault {
            // Debug log placeholder
        }
        #endif

        return smartDefault ?? accounts.first
    }

    // MARK: - Private Helpers

    /// Calculate recency score based on transaction dates
    /// - Parameter transactions: Transactions to analyze
    /// - Returns: Recency score (0-100 per transaction)
    private func calculateRecencyScore(for transactions: [Transaction]) -> Double {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var totalRecencyScore: Double = 0

        for transaction in transactions {
            // Parse date string to Date
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                // If parsing fails, treat as old transaction
                totalRecencyScore += 10
                continue
            }

            let daysSinceTransaction = Calendar.current.dateComponents([.day], from: transactionDate, to: now).day ?? 999

            let recencyPoints: Double
            switch daysSinceTransaction {
            case 0...1:
                recencyPoints = 100 // Last 24 hours
            case 2...7:
                recencyPoints = 70  // Last week
            case 8...30:
                recencyPoints = 40  // Last month
            default:
                recencyPoints = 10  // Older
            }

            totalRecencyScore += recencyPoints
        }

        return totalRecencyScore
    }

    // MARK: - Usage Statistics

    /// Get usage statistics for all accounts
    /// - Returns: Dictionary mapping account ID to usage count
    func getUsageStatistics() -> [String: Int] {
        let accountUsage = Dictionary(grouping: transactions.compactMap { $0.accountId }) { $0 }
        return accountUsage.mapValues { $0.count }
    }

    /// Get the most frequently used account
    /// - Returns: Account with most transactions, or nil
    func getMostFrequentAccount() -> Account? {
        let stats = getUsageStatistics()
        guard let mostUsedId = stats.max(by: { $0.value < $1.value })?.key else {
            return accounts.first
        }
        return accounts.first { $0.id == mostUsedId }
    }

    /// Get the most recently used account
    /// - Returns: Account with most recent transaction, or nil
    func getMostRecentAccount() -> Account? {
        guard let mostRecentTransaction = transactions.max(by: { $0.date < $1.date }) else {
            return accounts.first
        }

        guard let recentAccountId = mostRecentTransaction.accountId else {
            return accounts.first
        }

        return accounts.first { $0.id == recentAccountId }
    }
}

// MARK: - Debug Helper

#if DEBUG
extension AccountUsageTracker {
    /// Generate usage report for debugging
    func generateUsageReport() -> String {
        var report = """
        📊 Account Usage Report
        =======================

        Total Transactions: \(transactions.count)
        Total Accounts: \(accounts.count)

        """

        let stats = getUsageStatistics()
        let smartDefault = getSmartDefaultAccount()
        let mostFrequent = getMostFrequentAccount()
        let mostRecent = getMostRecentAccount()

        report += "\nUsage Statistics:\n"
        for (accountId, count) in stats.sorted(by: { $0.value > $1.value }) {
            let accountName = accounts.first { $0.id == accountId }?.name ?? "Unknown"
            report += "  - \(accountName): \(count) transactions\n"
        }

        report += "\nRecommendations:\n"
        report += "  Smart Default: \(smartDefault?.name ?? "None")\n"
        report += "  Most Frequent: \(mostFrequent?.name ?? "None")\n"
        report += "  Most Recent: \(mostRecent?.name ?? "None")\n"

        return report
    }
}
#endif
