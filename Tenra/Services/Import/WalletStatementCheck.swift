//
//  WalletStatementCheck.swift
//  Tenra
//
//  The Apple Pay payments LogWalletPaymentIntent saved on a statement's account
//  that the statement does not show (docs/plan-auto-capture.md §6). The Wallet
//  trigger also fires for a declined payment, and the action saves without asking,
//  so the statement is where such a payment shows up as missing. The review screen
//  lists them; the user decides, nothing is deleted on its own.
//
//  A payment counts as shown when an expense row has its amount within a day
//  (ImportDuplicateDetector.plainDayWindow), each row taken once. Only payments in
//  the account's currency are checked (a foreign one appears converted), dated from
//  the statement's first row to `settleDays` before its last (a charge can post days
//  after the tap). Pure and `nonisolated`, like ImportDuplicateDetector.
//

import Foundation

nonisolated enum WalletStatementCheck {

    /// Days a charge may take to reach the statement after the tap.
    static let settleDays = 2

    /// - Parameters:
    ///   - captured: the Wallet action's saved transactions (WalletCaptureStore).
    ///   - rows: the statement's rows.
    /// - Returns: the captured payments the statement does not show, oldest first.
    static func missing(
        captured: [Transaction],
        rows: [Transaction],
        accountId: String,
        accountCurrency: String
    ) -> [Transaction] {
        let rowDays = rows.compactMap { row in ImportDuplicateDetector.dayNumber(row.date).map { (row, $0) } }
        guard let first = rowDays.map({ $0.1 }).min(), let last = rowDays.map({ $0.1 }).max() else { return [] }

        var unclaimed = rowDays.filter { $0.0.type == .expense }
        var result: [Transaction] = []

        let candidates = captured
            .compactMap { tx -> (Transaction, Int)? in
                guard tx.accountId == accountId,
                      tx.type == .expense,
                      tx.currency == accountCurrency,
                      let day = ImportDuplicateDetector.dayNumber(tx.date),
                      day >= first, day <= last - settleDays else { return nil }
                return (tx, day)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }

        for (payment, day) in candidates {
            let match = unclaimed.indices
                .filter { index in
                    abs(unclaimed[index].1 - day) <= ImportDuplicateDetector.plainDayWindow
                        && abs(unclaimed[index].0.amount - payment.amount) < 0.005
                }
                .min { abs(unclaimed[$0].1 - day) < abs(unclaimed[$1].1 - day) }
            if let match {
                unclaimed.remove(at: match)
            } else {
                result.append(payment)
            }
        }
        return result
    }
}
