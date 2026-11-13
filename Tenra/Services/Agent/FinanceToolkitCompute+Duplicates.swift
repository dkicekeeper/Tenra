//
//  FinanceToolkitCompute+Duplicates.swift
//  Tenra
//
//  `find_duplicates` (docs/plan-ten-agent.md, order in the data): incomes and expenses of the
//  last twelve months that look recorded twice. The same day, type, amount and currency on the
//  same account (or with one of them on no account): what a statement imported over payments
//  that recorded themselves leaves behind. Two charges of one subscription series are not a
//  pair. A sweep over the history, run off the main actor on the read tools' snapshot. Nothing
//  is written: the assistant offers `draft_transaction_delete` for the extra ones.
//

import Foundation

extension FinanceToolkitCompute {
    /// The most groups one result lists, the newest first.
    nonisolated static let duplicateGroupLimit = 20

    nonisolated static func duplicates(_ s: FinanceSnapshot, calendar: Calendar = .current) -> JSONValue {
        let from = calendar.date(byAdding: .month, value: -12, to: s.now).map(FastDateParser.string(from:)) ?? s.today
        var groups: [String: [Transaction]] = [:]
        for tx in s.transactions where (tx.type == .expense || tx.type == .income) && tx.date >= from && tx.date <= s.today {
            let key = "\(tx.date)|\(tx.type.rawValue)|\(tx.currency)|\(Int((tx.amount * 100).rounded()))"
            groups[key, default: []].append(tx)
        }

        var found: [(date: String, value: JSONValue)] = []
        for (_, candidates) in groups where candidates.count > 1 {
            // Within one day and amount: split by account, a record on no account joining any.
            var byAccount: [String: [Transaction]] = [:]
            var loose: [Transaction] = []
            for tx in candidates {
                if let account = tx.accountId, !account.isEmpty {
                    byAccount[account, default: []].append(tx)
                } else {
                    loose.append(tx)
                }
            }
            var clusters = byAccount.values.map { $0 }
            if clusters.isEmpty {
                clusters = [loose]
            } else if !loose.isEmpty {
                clusters[0] += loose
            }
            for cluster in clusters where cluster.count > 1 {
                // Charges of one series on one day are the series' own business.
                let series = Set(cluster.compactMap(\.recurringSeriesId))
                if series.count == 1, cluster.allSatisfy({ $0.recurringSeriesId != nil }) { continue }
                let names = Set(cluster.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                let records = cluster.sorted { $0.id < $1.id }.map { tx -> JSONValue in
                    [
                        "transaction_id": .string(tx.id),
                        "merchant": .string(tx.description),
                        "category": .string(tx.category),
                        "account": tx.accountId.flatMap { s.accountNameById[$0] }.map(JSONValue.string) ?? .null,
                        "recurring": .bool(tx.recurringSeriesId != nil),
                    ]
                }
                guard let first = cluster.first else { continue }
                found.append((first.date, [
                    "date": .string(first.date),
                    "type": .string(first.type.rawValue),
                    "amount": .number(round2(first.amount)),
                    "currency": .string(first.currency),
                    // The same name on every record: almost surely one payment twice.
                    "same_merchant": .bool(names.count == 1),
                    "records": .array(records),
                ]))
            }
        }
        let sorted = found.sorted { $0.date > $1.date }
        return [
            "from": .string(from),
            "to": .string(s.today),
            "groups": .array(sorted.prefix(duplicateGroupLimit).map(\.value)),
            "count_total": .number(Double(sorted.count)),
        ]
    }
}
