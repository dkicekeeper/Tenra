//
//  ImportTransferMatcher.swift
//  Tenra
//
//  Finds the other side of a transfer between two of the user's accounts when
//  the second bank's statement is imported. A Freedom row "−50 000 ₸, 19.09" and a
//  Kaspi row "+50 000 ₸, 19.09" are one transfer; imported separately they became
//  an expense and an income, inflating both totals by 50 000.
//
//  Two outcomes per imported row:
//   • counterpart: a plain expense/income on another of the user's accounts
//     mirrors the row (opposite direction, same amount and currency, within
//     `dayWindow` days). Saving converts that transaction into one transfer and
//     does not add the row.
//   • alreadyTransfer: a saved transfer already moves this money out of / into
//     the row's account. The row starts unchecked.
//
//  Only rows whose statement operation can be a money movement are matched
//  (not purchases or cash withdrawals), saved rows that are themselves an
//  own-account move from elsewhere (a deposit) are never a counterpart, and each
//  saved transaction is claimed by at most one row. Checked against a real
//  Kaspi + Freedom pair (2026-09): 10 true pairs, and the two false ones this
//  deposit rule removes. Pure and `nonisolated`: runs over every saved transaction.
//

import Foundation

nonisolated enum ImportTransferMatcher {

    enum Match: Sendable, Equatable {
        case counterpart(existingId: String, accountId: String)
        case alreadyTransfer(existingId: String)
    }

    /// Interbank transfers land the same day or the next working day.
    static let dayWindow = 2

    /// - Parameters:
    ///   - imported: statement rows (not saved yet).
    ///   - importedAccounts: row id → the account the row will be saved to.
    ///   - eligibleRowIds: rows whose operation can be a transfer.
    ///   - ownAccountIds: accounts a counterpart may sit on (the user's regular accounts).
    ///   - existing: every saved transaction.
    static func detect(
        imported: [Transaction],
        importedAccounts: [String: String],
        eligibleRowIds: Set<String>,
        ownAccountIds: Set<String>,
        existing: [Transaction]
    ) -> [String: Match] {
        struct Candidate {
            let tx: Transaction
            let day: Int
        }
        // Existing transactions by (currency, amount in tiyn/cents): the only exact
        // key both sides share.
        var byAmount: [String: [Candidate]] = [:]
        for tx in existing {
            guard let day = ImportDuplicateDetector.dayNumber(tx.date) else { continue }
            switch tx.type {
            case .expense, .income:
                guard tx.recurringSeriesId == nil, let accountId = tx.accountId,
                      ownAccountIds.contains(accountId),
                      // A saved row that is itself a move from a third place ("Перевод
                      // вклада по Договору": deposit to card) is not this transfer's
                      // other side, even when the chain deposit → card → other bank →
                      // a person repeats the same amount on the same day.
                      StatementOperationKind.classify(operation: nil, details: tx.description) != .ownAccountTransfer
                else { continue }
                byAmount[amountKey(tx.currency, tx.amount), default: []].append(Candidate(tx: tx, day: day))
            case .internalTransfer:
                byAmount[amountKey(tx.currency, tx.amount), default: []].append(Candidate(tx: tx, day: day))
                if let targetCurrency = tx.targetCurrency, let targetAmount = tx.targetAmount,
                   amountKey(targetCurrency, targetAmount) != amountKey(tx.currency, tx.amount) {
                    byAmount[amountKey(targetCurrency, targetAmount), default: []].append(Candidate(tx: tx, day: day))
                }
            default:
                continue
            }
        }

        var claimed = Set<String>()
        var result: [String: Match] = [:]

        for row in imported.sorted(by: { $0.date < $1.date })
        where eligibleRowIds.contains(row.id) && (row.type == .expense || row.type == .income) {
            guard let accountId = importedAccounts[row.id],
                  let rowDay = ImportDuplicateDetector.dayNumber(row.date),
                  let candidates = byAmount[amountKey(row.currency, row.amount)] else { continue }
            let outgoing = row.type == .expense

            var bestTransfer: (tx: Transaction, distance: Int)?
            var bestCounterpart: (tx: Transaction, distance: Int)?
            for candidate in candidates where !claimed.contains(candidate.tx.id) {
                let distance = abs(candidate.day - rowDay)
                guard distance <= dayWindow else { continue }
                let tx = candidate.tx
                if tx.type == .internalTransfer {
                    let touches = outgoing
                        ? tx.accountId == accountId && tx.currency == row.currency
                        : tx.targetAccountId == accountId && (tx.targetCurrency ?? tx.currency) == row.currency
                    if touches, bestTransfer.map({ distance < $0.distance }) ?? true {
                        bestTransfer = (tx, distance)
                    }
                } else if tx.accountId != accountId,
                          tx.currency == row.currency,
                          tx.type == (outgoing ? .income : .expense),
                          bestCounterpart.map({ distance < $0.distance }) ?? true {
                    bestCounterpart = (tx, distance)
                }
            }

            if let match = bestTransfer {
                claimed.insert(match.tx.id)
                result[row.id] = .alreadyTransfer(existingId: match.tx.id)
            } else if let match = bestCounterpart, let counterpartAccount = match.tx.accountId {
                claimed.insert(match.tx.id)
                result[row.id] = .counterpart(existingId: match.tx.id, accountId: counterpartAccount)
            }
        }
        return result
    }

    private static func amountKey(_ currency: String, _ amount: Double) -> String {
        "\(currency)|\(Int((amount * 100).rounded()))"
    }
}
