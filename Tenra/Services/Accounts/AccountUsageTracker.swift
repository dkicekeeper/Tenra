//
//  AccountUsageTracker.swift
//  Tenra
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

    /// Activity window for "is this account still in use?" decision.
    /// Accounts with no transactions in this window are skipped entirely so
    /// dormant accounts can't win on accumulated historical volume.
    private static let activityWindowDays: Int = 90

    /// Get the smart default account based on usage statistics.
    /// - Parameter category: Optional category name. When provided, only
    ///   transactions in that category contribute to scoring — so e.g.
    ///   "Транспорт" returns the account most-used for transport in the
    ///   last 90 days, not the globally most-used account.
    /// - Returns: The most appropriate account, or nil if no accounts exist.
    ///
    /// Algorithm:
    /// 1. Filter each account's transactions to a rolling 90-day window
    ///    AND (if requested) to a single category. Accounts with zero
    ///    matching transactions are dropped — a dormant account, or an
    ///    account never used for this category, can never be the "smart
    ///    default" no matter how many transactions it accumulated.
    /// 2. For each remaining account, compute:
    ///    - Volume (40%): count of matching transactions.
    ///    - Freshness (60%): the MAX recency points across those
    ///      transactions (NOT the sum). Using max prevents accounts from
    ///      stacking recency by having many semi-old transactions.
    ///      Recency points: ≤24h = 100, ≤7d = 70, ≤30d = 40, else = 10.
    /// 3. If no account matches in this category, fall back to the global
    ///    smart default (no category filter), then to the most-recently-used
    ///    account ever, then to `accounts.first`.
    func getSmartDefaultAccount(forCategory category: String? = nil) -> Account? {
        guard !accounts.isEmpty else { return nil }
        guard !transactions.isEmpty else { return accounts.first }

        if let scored = scoreAccounts(forCategory: category),
           let topId = scored.max(by: { $0.value < $1.value })?.key,
           let account = accounts.first(where: { $0.id == topId }) {
            return account
        }

        // Per-category scoring produced nothing — fall back through the
        // ladder: global smart default → most-recent ever → first account.
        if category != nil,
           let global = getSmartDefaultAccount(forCategory: nil) {
            return global
        }
        return getMostRecentAccount() ?? accounts.first
    }

    /// Score each candidate account inside the activity window.
    /// Returns nil if no account had any matching transactions.
    private func scoreAccounts(forCategory category: String?) -> [String: Double]? {
        let dateFormatter = Self.recencyDateFormatter
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.activityWindowDays, to: now) ?? now
        let normalizedCategory = category?.lowercased()

        var scores: [String: Double] = [:]
        let grouped = Dictionary(grouping: transactions) { $0.accountId }

        for (accountId, accountTransactions) in grouped {
            guard let accountId = accountId else { continue }

            let matching = accountTransactions.filter { tx in
                guard let date = dateFormatter.date(from: tx.date), date >= cutoff else { return false }
                if let needle = normalizedCategory {
                    return tx.category.lowercased() == needle
                }
                return true
            }
            guard !matching.isEmpty else { continue }

            let volumeScore = Double(matching.count) * 0.4
            let freshnessScore = matching
                .map { recencyPoints(for: $0, now: now, dateFormatter: dateFormatter) }
                .max() ?? 0

            scores[accountId] = volumeScore + freshnessScore * 0.6
        }

        return scores.isEmpty ? nil : scores
    }

    /// Recency points for a single transaction. Pulled out so
    /// `getSmartDefaultAccount` can take the max instead of the sum.
    private func recencyPoints(for transaction: Transaction, now: Date, dateFormatter: DateFormatter) -> Double {
        guard let date = dateFormatter.date(from: transaction.date) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 999
        switch days {
        case 0...1: return 100
        case 2...7: return 70
        case 8...30: return 40
        default: return 10
        }
    }

    // MARK: - Private Helpers

    /// Cached DateFormatter — DateFormatter is Sendable on iOS 26+ target
    private static let recencyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Calculate recency score based on transaction dates
    /// - Parameter transactions: Transactions to analyze
    /// - Returns: Recency score (0-100 per transaction)
    private func calculateRecencyScore(for transactions: [Transaction]) -> Double {
        let now = Date()
        let dateFormatter = Self.recencyDateFormatter

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
