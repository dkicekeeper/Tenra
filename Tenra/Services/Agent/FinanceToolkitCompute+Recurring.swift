//
//  FinanceToolkitCompute+Recurring.swift
//  Tenra
//
//  `find_recurring_candidates` (docs/plan-ten-agent.md stage 2): expenses of the last year that
//  look like a subscription or a regular payment and are not one yet. The same merchant three
//  times or more, at even intervals (a week, a month, a quarter, a year) and for about the same
//  amount. A sweep over the history, run off the main actor on the read tools' snapshot.
//  Nothing is written: the assistant offers `draft_recurring` for what the person picks.
//

import Foundation

extension FinanceToolkitCompute {
    /// The most candidates one result lists, the most regular first.
    nonisolated static let recurringCandidateLimit = 10

    private nonisolated struct Rhythm: Sendable {
        let frequency: String
        let days: ClosedRange<Int>
        let component: Calendar.Component
        let value: Int
        let minimumCount: Int
    }

    private nonisolated static let rhythms = [
        Rhythm(frequency: "weekly", days: 6...8, component: .day, value: 7, minimumCount: 4),
        Rhythm(frequency: "monthly", days: 26...35, component: .month, value: 1, minimumCount: 3),
        Rhythm(frequency: "quarterly", days: 85...97, component: .month, value: 3, minimumCount: 3),
        Rhythm(frequency: "yearly", days: 355...375, component: .year, value: 1, minimumCount: 2),
    ]

    /// - Parameter knownNames: the names of the series the person already has, lowercased: a
    ///   merchant that is one of them is left out.
    nonisolated static func recurringCandidates(_ s: FinanceSnapshot, knownNames: Set<String>, calendar: Calendar = .current) -> JSONValue {
        guard let yearAgo = calendar.date(byAdding: .month, value: -13, to: s.now) else { return ["candidates": []] }
        let from = FastDateParser.string(from: yearAgo)
        var groups: [String: [Transaction]] = [:]
        for tx in s.transactions where tx.type == .expense && tx.recurringSeriesId == nil && tx.date >= from && tx.date <= s.today {
            let key = tx.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key.count >= 2, !knownNames.contains(key) else { continue }
            groups[key + "|" + tx.currency, default: []].append(tx)
        }

        var found: [(spread: Double, row: JSONValue)] = []
        for (_, transactions) in groups where transactions.count >= 2 {
            let sorted = transactions.sorted { $0.date < $1.date }
            let dates = sorted.compactMap { FastDateParser.date(from: $0.date) }
            guard dates.count == sorted.count else { continue }
            let gaps = zip(dates, dates.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }
            guard let rhythm = rhythms.first(where: { rhythm in
                sorted.count >= rhythm.minimumCount && gaps.allSatisfy { rhythm.days.contains($0) }
            }) else { continue }
            let amounts = sorted.map(\.amount).sorted()
            let median = amounts[amounts.count / 2]
            guard median > 0, let low = amounts.first, let high = amounts.last else { continue }
            let spread = (high - low) / median
            guard spread <= 0.15, let last = sorted.last, let lastDate = dates.last else { continue }
            var next = lastDate
            // The next charge after today, stepping from the last one.
            for _ in 0..<60 where FastDateParser.string(from: next) <= s.today {
                guard let stepped = calendar.date(byAdding: rhythm.component, value: rhythm.value, to: next) else { break }
                next = stepped
            }
            found.append((spread, [
                "name": .string(last.description.trimmingCharacters(in: .whitespacesAndNewlines)),
                "amount": .number(round2(median)),
                "currency": .string(last.currency),
                "frequency": .string(rhythm.frequency),
                "times": .number(Double(sorted.count)),
                "last_date": .string(last.date),
                "next_date": .string(FastDateParser.string(from: next)),
                "category_id": s.categoryIdByName[last.category].map(JSONValue.string) ?? .null,
                "category": .string(last.category),
                "account_id": last.accountId.map(JSONValue.string) ?? .null,
                "account": last.accountId.flatMap { s.accountNameById[$0] }.map(JSONValue.string) ?? .null,
            ]))
        }
        let rows = found
            .sorted { ($0.spread, $0.row["name"]?.stringValue ?? "") < ($1.spread, $1.row["name"]?.stringValue ?? "") }
            .prefix(recurringCandidateLimit)
            .map(\.row)
        return ["candidates": .array(Array(rows)), "count_total": .number(Double(found.count))]
    }
}
