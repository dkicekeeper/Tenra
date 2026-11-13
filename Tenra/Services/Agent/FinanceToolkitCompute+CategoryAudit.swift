//
//  FinanceToolkitCompute+CategoryAudit.swift
//  Tenra
//
//  `get_category_audit` (docs/plan-ten-agent.md, order in the data): how the person's
//  categories and subcategories are used over the last twelve months, for the assistant to
//  suggest a tidier set. Per category: records and their total in the base currency, its share
//  of its type, the last record, the merchants that fill it, its subcategories with their use
//  and the records left without one; apart, the records whose category no longer exists. A
//  sweep over the history, run off the main actor on the read tools' snapshot. Nothing is
//  written: the changes go through `draft_category_change` and `draft_recategorize`.
//

import Foundation

extension FinanceToolkitCompute {
    nonisolated struct AuditCategory: Sendable {
        nonisolated struct Sub: Sendable {
            let id: String
            let name: String
        }

        let id: String
        let name: String
        let isIncome: Bool
        let hasBudget: Bool
        let subcategories: [Sub]
    }

    /// The most merchants one category lists.
    nonisolated static let auditMerchantLimit = 5

    private nonisolated struct AuditTally {
        var records = 0
        var total = 0.0
        var recordsAllTime = 0
        var lastDate: String?
        var merchants: [String: Int] = [:]
        var withoutSubcategory = 0
        var bySubcategory: [String: Int] = [:]
    }

    /// - Parameter subcategoryIdsByTransaction: the subcategories each record is tagged with.
    nonisolated static func categoryAudit(
        _ s: FinanceSnapshot,
        categories: [AuditCategory],
        subcategoryIdsByTransaction: [String: [String]],
        calendar: Calendar = .current
    ) -> JSONValue {
        let from = calendar.date(byAdding: .month, value: -12, to: s.now).map(FastDateParser.string(from:)) ?? s.today
        let rates = RateSnapshot()
        // A name may be used by an expense and an income category: the type tells them apart.
        func key(_ name: String, income: Bool) -> String { "\(income ? "i" : "e")|\(name)" }
        let known = Set(categories.map { key($0.name, income: $0.isIncome) })

        var tallies: [String: AuditTally] = [:]
        var lostRecords = 0
        var lostTotal = 0.0
        var typeTotals: [Bool: Double] = [:]
        for tx in s.transactions where (tx.type == .expense || tx.type == .income) && tx.date <= s.today {
            let income = tx.type == .income
            let id = key(tx.category, income: income)
            let inPeriod = tx.date >= from
            guard known.contains(id) else {
                if inPeriod {
                    lostRecords += 1
                    lostTotal += baseAmount(tx, base: s.baseCurrency, rates: rates)
                }
                continue
            }
            var tally = tallies[id] ?? AuditTally()
            tally.recordsAllTime += 1
            if tally.lastDate.map({ tx.date > $0 }) ?? true { tally.lastDate = tx.date }
            if inPeriod {
                let amount = baseAmount(tx, base: s.baseCurrency, rates: rates)
                tally.records += 1
                tally.total += amount
                typeTotals[income, default: 0] += amount
                let merchant = tx.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !merchant.isEmpty { tally.merchants[merchant, default: 0] += 1 }
                let tags = subcategoryIdsByTransaction[tx.id] ?? []
                if tags.isEmpty { tally.withoutSubcategory += 1 }
                for tag in tags { tally.bySubcategory[tag, default: 0] += 1 }
            }
            tallies[id] = tally
        }

        let rows: [(total: Double, name: String, value: JSONValue)] = categories.map { category in
            let tally = tallies[key(category.name, income: category.isIncome)] ?? AuditTally()
            let typeTotal = typeTotals[category.isIncome] ?? 0
            let merchants = tally.merchants
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(auditMerchantLimit)
                .map { JSONValue.object(["name": .string($0.key), "records": .number(Double($0.value))]) }
            let subcategories = category.subcategories.map { sub in
                JSONValue.object(["id": .string(sub.id), "name": .string(sub.name), "records": .number(Double(tally.bySubcategory[sub.id] ?? 0))])
            }
            let value: JSONValue = [
                "id": .string(category.id),
                "name": .string(category.name),
                "type": .string(category.isIncome ? "income" : "expense"),
                "records": .number(Double(tally.records)),
                "total": .number(round2(tally.total)),
                "share_percent": .number(typeTotal > 0 ? (tally.total / typeTotal * 1000).rounded() / 10 : 0),
                "last_date": tally.lastDate.map(JSONValue.string) ?? .null,
                // Never used at all, and used before but not in these twelve months.
                "unused": .bool(tally.recordsAllTime == 0),
                "idle": .bool(tally.recordsAllTime > 0 && tally.records == 0),
                "has_budget": .bool(category.hasBudget),
                "top_merchants": .array(Array(merchants)),
                "subcategories": .array(subcategories),
                "without_subcategory": .number(Double(category.subcategories.isEmpty ? 0 : tally.withoutSubcategory)),
            ]
            return (tally.total, category.name, value)
        }
        let sorted = rows.sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        return [
            "from": .string(from),
            "to": .string(s.today),
            "currency": .string(s.baseCurrency),
            "categories": .array(sorted.map(\.value)),
            "without_category": ["records": .number(Double(lostRecords)), "total": .number(round2(lostTotal))],
        ]
    }
}
