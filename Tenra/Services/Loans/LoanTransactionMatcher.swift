//
//  LoanTransactionMatcher.swift
//  Tenra
//
//  Finds existing transactions that match a loan's payment pattern.
//  Used during loan onboarding to identify past payments the user
//  already recorded as regular expenses.
//

import Foundation

/// Finds existing transactions that match a loan's payment pattern.
nonisolated enum LoanTransactionMatcher {

    /// Default tolerance: +/-10% of monthly payment.
    static let defaultTolerance: Double = 0.10

    /// Returns expense transactions whose amount falls within `tolerance` of
    /// the loan's `monthlyPayment`, dated after the loan start, and matching
    /// the loan currency. Results are sorted chronologically.
    static func findCandidates(
        for loan: Account,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance
    ) -> [Transaction] {
        guard let loanInfo = loan.loanInfo else { return [] }

        let monthlyPayment = NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue
        let lowerBound = monthlyPayment * (1.0 - tolerance)
        let upperBound = monthlyPayment * (1.0 + tolerance)
        let startDate = loanInfo.startDate
        let loanCurrency = loan.currency

        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.currency == loanCurrency else { return false }
                guard tx.amount >= lowerBound && tx.amount <= upperBound else { return false }
                guard tx.date >= startDate else { return false }
                return true
            }
            .sorted { $0.date < $1.date }
    }
}
