//
//  ImportDuplicateDetector.swift
//  Tenra
//
//  Flags statement rows that are already in Tenra, so the review screen can
//  leave them unchecked. Two cases:
//   • the same operation was imported or entered before (same account, type,
//     currency and amount, within a day: bank posting dates drift by one);
//   • a subscription series already auto-generated this charge (series
//     occurrences are realized on their due date, so the bank charge for the
//     same subscription would otherwise count twice);
//   • a loan payment recorded through the loans screen: its own type, but the
//     money left this same account, and the statement shows it as a plain
//     expense ("Платеж по кредиту").
//
//  Descriptions are deliberately NOT compared: a manual entry ("Кофе") and the
//  bank's merchant string ("STARBUCKS 123") rarely match. Pure and nonisolated
//  so it runs off the main actor over the full transaction set.
//

import Foundation

nonisolated enum ImportDuplicateDetector {

    enum Reason: Sendable, Equatable {
        case alreadyAdded(existingId: String)
        case subscriptionOccurrence(existingId: String, seriesId: String)
        case loanPayment(existingId: String)

        var existingId: String {
            switch self {
            case .alreadyAdded(let id), .subscriptionOccurrence(let id, _), .loanPayment(let id): return id
            }
        }
    }

    /// Max days between the imported row and an existing plain duplicate.
    static let plainDayWindow = 1
    /// Max days / relative amount difference for a subscription occurrence match.
    static let subscriptionDayWindow = 3
    static let subscriptionAmountTolerance = 0.05
    /// Max days between a statement row and a loan payment recorded in Tenra: the
    /// payment is often logged on its due date, the bank debit may land around it.
    static let loanPaymentDayWindow = 3

    /// - Parameters:
    ///   - imported: rows from the statement (not saved yet).
    ///   - importedAccounts: imported id → the account the review screen assigns by default.
    ///     Rows without an account are never flagged.
    ///   - existing: every saved transaction.
    /// - Returns: imported id → reason, for flagged rows only. Each existing transaction
    ///   is claimed by at most one imported row (closest date wins, rows processed by date).
    static func detect(
        imported: [Transaction],
        importedAccounts: [String: String],
        existing: [Transaction]
    ) -> [String: Reason] {
        struct BucketKey: Hashable {
            let accountId: String
            let type: TransactionType
            let currency: String
        }

        var buckets: [BucketKey: [(tx: Transaction, day: Int)]] = [:]
        for tx in existing {
            guard let accountId = tx.accountId, let day = dayNumber(tx.date) else { continue }
            // A loan payment's `accountId` is the paying bank account; on that
            // account's statement it is an ordinary expense.
            let type: TransactionType = tx.type == .loanPayment || tx.type == .loanEarlyRepayment ? .expense : tx.type
            buckets[BucketKey(accountId: accountId, type: type, currency: tx.currency), default: []]
                .append((tx, day))
        }

        var claimed = Set<String>()
        var result: [String: Reason] = [:]

        for row in imported.sorted(by: { $0.date < $1.date }) {
            guard let accountId = importedAccounts[row.id],
                  let rowDay = dayNumber(row.date),
                  let candidates = buckets[BucketKey(accountId: accountId, type: row.type, currency: row.currency)]
            else { continue }

            var bestSubscription: (tx: Transaction, distance: Int)?
            var bestLoan: (tx: Transaction, distance: Int)?
            var bestPlain: (tx: Transaction, distance: Int)?

            for candidate in candidates where !claimed.contains(candidate.tx.id) {
                let distance = abs(candidate.day - rowDay)
                if candidate.tx.type == .loanPayment || candidate.tx.type == .loanEarlyRepayment {
                    if distance <= loanPaymentDayWindow,
                       abs(candidate.tx.amount - row.amount) < 0.005,
                       bestLoan.map({ distance < $0.distance }) ?? true {
                        bestLoan = (candidate.tx, distance)
                    }
                } else if let seriesId = candidate.tx.recurringSeriesId, !seriesId.isEmpty,
                   row.type == .expense,
                   distance <= subscriptionDayWindow,
                   abs(candidate.tx.amount - row.amount) <= subscriptionAmountTolerance * row.amount {
                    if bestSubscription == nil || distance < bestSubscription!.distance {
                        bestSubscription = (candidate.tx, distance)
                    }
                } else if distance <= plainDayWindow,
                          abs(candidate.tx.amount - row.amount) < 0.005 {
                    if bestPlain == nil || distance < bestPlain!.distance {
                        bestPlain = (candidate.tx, distance)
                    }
                }
            }

            if let match = bestSubscription, let seriesId = match.tx.recurringSeriesId {
                claimed.insert(match.tx.id)
                result[row.id] = .subscriptionOccurrence(existingId: match.tx.id, seriesId: seriesId)
            } else if let match = bestLoan {
                claimed.insert(match.tx.id)
                result[row.id] = .loanPayment(existingId: match.tx.id)
            } else if let match = bestPlain {
                claimed.insert(match.tx.id)
                result[row.id] = .alreadyAdded(existingId: match.tx.id)
            }
        }
        return result
    }

    /// Whole days since the reference date for a "yyyy-MM-dd" key (FastDateParser, not
    /// DateFormatter: this runs over every saved transaction). Shared with
    /// `ImportTransferMatcher`.
    static func dayNumber(_ key: String) -> Int? {
        guard let date = FastDateParser.date(from: key) else { return nil }
        // Shift local midnight to UTC before dividing, so DST changes cannot make two
        // consecutive local days share a number.
        let local = date.timeIntervalSinceReferenceDate + Double(TimeZone.current.secondsFromGMT(for: date))
        return Int((local / 86_400).rounded(.down))
    }
}
