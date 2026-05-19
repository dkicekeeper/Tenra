//
//  SubscriptionTransactionMatcher.swift
//  Tenra
//
//  Finds existing transactions that match a subscription's payment pattern.
//  Used to retroactively link manually entered transactions to a subscription.
//
//  Complexity note: this is intrinsically O(N_tx) — we have to consider every
//  unlinked expense to test amount/currency match (FX conversion per tx).
//  This is acceptable because:
//   1. The caller (`LinkPaymentsView.reloadBaseline`) runs it in
//      `Task.detached(priority: .userInitiated)` with a spinner — never blocks UI.
//   2. The screen is one-shot, user-initiated. Not a 60 fps hot path.
//   3. Adding a dedicated `unlinkedExpenseIds` index would yield ≤2× speedup but
//      cost permanent maintenance in `updateState` and edge cases for
//      loan/deposit pseudo-expenses. Not worth the long-term tax.
//
//  See docs/domains/accounts.md for the broader O(1) index family used by
//  other consumers (`transactionsByAccount`, `transactionsBySeriesId`, etc.).
//

import Foundation

/// Amount-matching mode used by the link-payments UI.
enum AmountMatchMode: String, CaseIterable, Sendable {
    /// Include any unlinked expense transaction — useful for historical price drift.
    case all
    /// Amount within ±30% (default).
    case tolerance
    /// Amount must equal the subscription amount exactly.
    case exact
}

/// Finds existing transactions that match a subscription's payment pattern.
nonisolated enum SubscriptionTransactionMatcher {

    /// Default tolerance: +/-30% of subscription amount.
    /// Covers historical price hikes (e.g. Apple Music 1450 → 1690 → 2290 KZT over 2 years).
    static let defaultTolerance: Double = 0.30

    /// Returns expense transactions whose amount matches the subscription's amount.
    ///
    /// Matching logic:
    /// - `.all`:        no amount constraint (all unlinked expense transactions).
    /// - `.tolerance`:  amount within ±`tolerance` (cross-currency via FX).
    /// - `.exact`:      amount must equal subscription amount exactly (cross-currency via FX).
    ///
    /// Cross-currency: same-currency compares `tx.amount` directly; otherwise converts
    /// subscription amount → tx.currency via `CurrencyConverter.convertSync`. Falls back
    /// to `tx.convertedAmount` / `tx.targetAmount` if the FX rate isn't cached.
    ///
    /// Results are sorted chronologically (oldest first).
    static func findCandidates(
        for subscription: RecurringSeries,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance,
        mode: AmountMatchMode = .tolerance
    ) -> [Transaction] {
        let subAmount = NSDecimalNumber(decimal: subscription.amount).doubleValue
        let subCurrency = subscription.currency

        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.recurringSeriesId == nil else { return false }

                // "All" mode: no amount constraint.
                if mode == .all { return true }

                let exactMatch = mode == .exact

                // Target amount in tx's currency — either direct (same currency)
                // or converted from subscription currency via FX.
                let target: Double?
                if tx.currency == subCurrency {
                    target = subAmount
                } else if let converted = CurrencyConverter.convertSync(
                    amount: subAmount, from: subCurrency, to: tx.currency
                ) {
                    target = converted
                } else {
                    target = nil
                }

                if let target = target {
                    let lower = exactMatch ? target : target * (1.0 - tolerance)
                    let upper = exactMatch ? target : target * (1.0 + tolerance)
                    if tx.amount >= lower && tx.amount <= upper { return true }
                }

                // Fallback for multi-currency transfer records where the converted/target amount
                // is already stored on the transaction in subscription currency.
                let subLower = exactMatch ? subAmount : subAmount * (1.0 - tolerance)
                let subUpper = exactMatch ? subAmount : subAmount * (1.0 + tolerance)

                if let convertedAmount = tx.convertedAmount,
                   convertedAmount >= subLower && convertedAmount <= subUpper {
                    return true
                }
                if let targetAmount = tx.targetAmount,
                   targetAmount >= subLower && targetAmount <= subUpper {
                    return true
                }
                return false
            }
            .sorted { $0.date < $1.date }
    }
}
