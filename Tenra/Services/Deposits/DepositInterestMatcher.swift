//
//  DepositInterestMatcher.swift
//  Tenra
//
//  Finds existing income transactions that look like interest payments
//  on a deposit account. Used in DepositLinkInterestView to retroactively
//  mark bank-paid income as `.depositInterestAccrual`.
//

import Foundation

/// Finds existing transactions that match a deposit's interest-payment pattern.
nonisolated enum DepositInterestMatcher {

    /// Default tolerance: +/-30% of expected monthly interest.
    /// Wide because principal grows over time (with capitalization) and
    /// rate changes shift the "expected" amount.
    static let defaultTolerance: Double = 0.30

    /// Returns income transactions on the deposit account that fall
    /// within the expected interest-amount range and are dated after
    /// the deposit's first interest calculation date.
    ///
    /// - `.all`:        every income tx on the deposit account (no amount filter)
    /// - `.tolerance`:  amount within ±`tolerance` of expected monthly interest
    /// - `.exact`:      amount equals expected monthly interest exactly
    static func findCandidates(
        for deposit: Account,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance,
        mode: AmountMatchMode = .all
    ) -> [Transaction] {
        guard let info = deposit.depositInfo else { return [] }

        let depositCurrency = deposit.currency
        let depositId = deposit.id

        // Expected monthly interest ≈ balance × (annualRate / 100) / 12.
        // Crude single-point estimate; actual payments vary as balance grows.
        let principalD = deposit.balance
        let rateD = NSDecimalNumber(decimal: info.interestRateAnnual).doubleValue
        let expectedMonthly = principalD * (rateD / 100.0) / 12.0

        return transactions
            .filter { tx in
                guard tx.type == .income else { return false }
                guard tx.accountId == depositId else { return false }
                guard tx.currency == depositCurrency else { return false }
                // No date filter: deposits are often created after historical
                // income transactions already exist on the account.

                switch mode {
                case .all:
                    return true
                case .tolerance:
                    guard expectedMonthly > 0 else { return true }
                    let lower = expectedMonthly * (1.0 - tolerance)
                    let upper = expectedMonthly * (1.0 + tolerance)
                    return tx.amount >= lower && tx.amount <= upper
                case .exact:
                    return tx.amount == expectedMonthly
                }
            }
            .sorted { $0.date < $1.date }
    }
}
