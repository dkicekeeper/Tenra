//
//  FinanceToolkitCompute.swift
//  Tenra
//
//  The pure, off-main-actor part of the assistant's read tools: walks over a snapshot of the
//  user's transactions (docs/concurrency.md, DataSnapshot pattern). Totals go through
//  `SummaryCalculator.compute`, so income and expense classification and the conversion to the
//  base currency are the app's own rules (`TransactionType.summaryContribution`), never a
//  second copy of them.
//

import Foundation

nonisolated struct FinanceToolError: Error, Equatable {
    let message: String
}

/// Everything the read tools need, captured on the main actor.
nonisolated struct FinanceSnapshot: Sendable {
    let transactions: [Transaction]
    let baseCurrency: String
    let now: Date
    /// Today as `yyyy-MM-dd`: realized figures exclude future-dated transactions.
    let today: String
    let categoryIdByName: [String: String]
    let categoryNameById: [String: String]
    let accountNameById: [String: String]
}

nonisolated enum FinanceToolkitCompute {
    enum Kind: String, Sendable { case expense, income }

    struct Period: Sendable, Equatable {
        let from: String
        let to: String
        let start: Date
        let end: Date

        /// Inclusive `from`/`to` days; `end` is the exclusive bound `SummaryCalculator` expects.
        init(from: String, to: String) throws {
            guard let start = FastDateParser.date(from: from), let last = FastDateParser.date(from: to) else {
                throw FinanceToolError(message: "Dates must be YYYY-MM-DD.")
            }
            guard start <= last else { throw FinanceToolError(message: "`from` must not be after `to`.") }
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else {
                throw FinanceToolError(message: "Invalid date range.")
            }
            self.from = from
            self.to = to
            self.start = start
            self.end = end
        }
    }

    static let groupLimit = 15

    // MARK: - Spending summary

    static func spendingSummary(_ s: FinanceSnapshot, period: Period, kind: Kind, categoryIds: [String]?, accountIds: [String]?, groupBy: String) throws -> JSONValue {
        let txs = try matching(s, period: period, kind: kind, categoryIds: categoryIds, accountIds: accountIds)
        let total = sum(txs, kind: kind, period: period, snapshot: s)
        return [
            "currency": .string(s.baseCurrency),
            "type": .string(kind.rawValue),
            "from": .string(period.from),
            "to": .string(period.to),
            "total": .number(round2(total)),
            "count": .number(Double(txs.count)),
            "groups": .array(try groups(txs, by: groupBy, kind: kind, period: period, snapshot: s, total: total)),
        ]
    }

    // MARK: - Compare periods

    static func comparePeriods(_ s: FinanceSnapshot, current: Period, previous: Period, kind: Kind, groupBy: String) throws -> JSONValue {
        let a = try matching(s, period: current, kind: kind, categoryIds: nil, accountIds: nil)
        let b = try matching(s, period: previous, kind: kind, categoryIds: nil, accountIds: nil)
        let totalA = sum(a, kind: kind, period: current, snapshot: s)
        let totalB = sum(b, kind: kind, period: previous, snapshot: s)

        var rows: [JSONValue] = []
        if groupBy != "none" {
            let groupsA = Dictionary(uniqueKeysWithValues: try groupTotals(a, by: groupBy, kind: kind, period: current, snapshot: s).map { ($0.key, $0) })
            let groupsB = Dictionary(uniqueKeysWithValues: try groupTotals(b, by: groupBy, kind: kind, period: previous, snapshot: s).map { ($0.key, $0) })
            let keys = Set(groupsA.keys).union(groupsB.keys)
            let merged = keys.map { key -> (key: String, label: String, current: Double, previous: Double) in
                (key, groupsA[key]?.label ?? groupsB[key]?.label ?? key, groupsA[key]?.total ?? 0, groupsB[key]?.total ?? 0)
            }
            rows = merged
                .sorted { abs($0.current - $0.previous) > abs($1.current - $1.previous) }
                .prefix(groupLimit)
                .map { row in
                    [
                        "key": .string(row.key),
                        "label": .string(row.label),
                        "current": .number(round2(row.current)),
                        "previous": .number(round2(row.previous)),
                        "change": .number(round2(row.current - row.previous)),
                    ]
                }
        }
        return [
            "currency": .string(s.baseCurrency),
            "type": .string(kind.rawValue),
            "current": ["from": .string(current.from), "to": .string(current.to), "total": .number(round2(totalA))],
            "previous": ["from": .string(previous.from), "to": .string(previous.to), "total": .number(round2(totalB))],
            "change": .number(round2(totalA - totalB)),
            "change_percent": totalB != 0 ? .number(round2((totalA - totalB) / totalB * 100)) : .null,
            "groups": .array(rows),
        ]
    }

    // MARK: - Search

    struct SearchQuery: Sendable {
        var text: String?
        var period: Period?
        var type: String = "any"
        var categoryIds: [String]?
        var accountIds: [String]?
        var minAmount: Double?
        var maxAmount: Double?
        var largestFirst = false
        var limit = 20
    }

    static func search(_ s: FinanceSnapshot, _ q: SearchQuery) -> JSONValue {
        let rates = RateSnapshot()
        let names = q.categoryIds.map { Set($0.compactMap { s.categoryNameById[$0] }) }
        let accounts = q.accountIds.map(Set.init)
        let needle = q.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var found: [(tx: Transaction, base: Double)] = []
        for tx in s.transactions where tx.date <= s.today {
            if let period = q.period, tx.date < period.from || tx.date > period.to { continue }
            switch q.type {
            case "expense", "income":
                guard contributes(tx, kind: Kind(rawValue: q.type) ?? .expense) else { continue }
            case "transfer":
                guard tx.type.summaryContribution(isFuture: false) == .internalTransfer else { continue }
            default: break
            }
            if let names, !names.contains(tx.category) { continue }
            if let accounts, !(tx.accountId.map(accounts.contains) ?? false) { continue }
            if let needle, !needle.isEmpty,
               !tx.description.lowercased().contains(needle), !tx.category.lowercased().contains(needle) { continue }
            let base = baseAmount(tx, base: s.baseCurrency, rates: rates)
            if let min = q.minAmount, base < min { continue }
            if let max = q.maxAmount, base > max { continue }
            found.append((tx, base))
        }
        if q.largestFirst {
            found.sort { $0.base > $1.base }
        } else {
            found.sort { ($0.tx.date, $0.tx.createdAt) > ($1.tx.date, $1.tx.createdAt) }
        }
        let items: [JSONValue] = found.prefix(min(max(q.limit, 1), 50)).map { row in
            let tx = row.tx
            return [
                "id": .string(tx.id),
                "date": .string(tx.date),
                "type": .string(tx.type.rawValue),
                "amount": .number(round2(tx.amount)),
                "currency": .string(tx.currency),
                "amount_base": .number(round2(row.base)),
                "category_id": s.categoryIdByName[tx.category].map(JSONValue.string) ?? .null,
                "category": .string(tx.category),
                "merchant": .string(tx.description),
                "account_id": tx.accountId.map(JSONValue.string) ?? .null,
                "account": tx.accountId.flatMap { s.accountNameById[$0] }.map(JSONValue.string) ?? .null,
            ]
        }
        return ["currency": .string(s.baseCurrency), "count_total": .number(Double(found.count)), "items": .array(items)]
    }

    // MARK: - Helpers

    static func contributes(_ tx: Transaction, kind: Kind) -> Bool {
        let contribution = tx.type.summaryContribution(isFuture: false)
        return kind == .expense ? contribution == .expense : contribution == .income
    }

    static func matching(_ s: FinanceSnapshot, period: Period, kind: Kind, categoryIds: [String]?, accountIds: [String]?) throws -> [Transaction] {
        var names: Set<String>?
        if let categoryIds, !categoryIds.isEmpty {
            let resolved = categoryIds.compactMap { s.categoryNameById[$0] }
            guard !resolved.isEmpty else { throw FinanceToolError(message: "Unknown category ids: \(categoryIds.joined(separator: ", ")). Use ids from <app_context>.") }
            names = Set(resolved)
        }
        let accounts = accountIds.flatMap { $0.isEmpty ? nil : Set($0) }
        return s.transactions.filter { tx in
            tx.date >= period.from && tx.date <= period.to && tx.date <= s.today
                && (names?.contains(tx.category) ?? true)
                && (accounts.map { ids in tx.accountId.map(ids.contains) ?? false } ?? true)
                && contributes(tx, kind: kind)
        }
    }

    static func sum(_ txs: [Transaction], kind: Kind, period: Period, snapshot s: FinanceSnapshot) -> Double {
        let summary = SummaryCalculator.compute(transactions: txs, filterStart: period.start, filterEnd: period.end, baseCurrency: s.baseCurrency, now: s.now)
        return kind == .expense ? summary.totalExpenses : summary.totalIncome
    }

    struct GroupTotal: Sendable {
        let key: String
        let label: String
        let total: Double
        let count: Int
    }

    static func groupTotals(_ txs: [Transaction], by: String, kind: Kind, period: Period, snapshot s: FinanceSnapshot) throws -> [GroupTotal] {
        var buckets: [String: [Transaction]] = [:]
        var labels: [String: String] = [:]
        for tx in txs {
            let key: String
            let label: String
            switch by {
            case "category":
                key = s.categoryIdByName[tx.category] ?? tx.category
                label = tx.category
            case "merchant":
                let merchant = tx.description.trimmingCharacters(in: .whitespacesAndNewlines)
                key = merchant.isEmpty ? tx.category : merchant
                label = key
            case "week":
                key = weekStart(of: tx.date)
                label = key
            case "month":
                key = String(tx.date.prefix(7))
                label = key
            default:
                throw FinanceToolError(message: "group_by must be none, category, merchant, week or month.")
            }
            buckets[key, default: []].append(tx)
            labels[key] = label
        }
        return buckets.map { key, list in
            GroupTotal(key: key, label: labels[key] ?? key, total: sum(list, kind: kind, period: period, snapshot: s), count: list.count)
        }
    }

    static func groups(_ txs: [Transaction], by: String, kind: Kind, period: Period, snapshot s: FinanceSnapshot, total: Double) throws -> [JSONValue] {
        guard by != "none" else { return [] }
        var rows = try groupTotals(txs, by: by, kind: kind, period: period, snapshot: s)
        if by == "week" || by == "month" {
            rows.sort { $0.key < $1.key }
        } else {
            rows.sort { $0.total > $1.total }
            if rows.count > groupLimit {
                let rest = rows[(groupLimit - 1)...]
                rows = Array(rows.prefix(groupLimit - 1)) + [GroupTotal(key: "other", label: "other", total: rest.reduce(0) { $0 + $1.total }, count: rest.reduce(0) { $0 + $1.count })]
            }
        }
        return rows.map { row in
            [
                "key": .string(row.key),
                "label": .string(row.label),
                "total": .number(round2(row.total)),
                "count": .number(Double(row.count)),
                "share": .number(total > 0 ? (row.total / total * 1000).rounded() / 1000 : 0),
            ]
        }
    }

    /// Mirrors `SummaryCalculator`'s conversion (the canonical one): same currency as is, else
    /// the frozen FX table, else `convertedAmount` as a cold-cache fallback (red flag 6).
    static func baseAmount(_ tx: Transaction, base: String, rates: RateSnapshot) -> Double {
        if tx.currency == base { return tx.amount }
        if let converted = rates.convert(tx.amount, from: tx.currency, to: base) { return converted }
        return tx.convertedAmount ?? tx.amount
    }

    static func weekStart(of day: String) -> String {
        guard let date = FastDateParser.date(from: day) else { return day }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = Calendar.current.timeZone
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return day }
        return FastDateParser.string(from: start)
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
