//
//  FinanceToolkitCompute+BudgetSuggestions.swift
//  Tenra
//
//  `suggest_budgets` (docs/plan-ten-agent.md, order in the data): what each expense category
//  took in each of the last three whole months, in the base currency, next to the monthly
//  budget it has, so the assistant can offer limits that follow what is really spent: a budget
//  for a large category that has none, a higher one where every month went over, a lower one
//  where a third of it is left every month. A sweep over the history, run off the main actor
//  on the read tools' snapshot. Nothing is written: the limits go through `draft_budget`.
//

import Foundation

extension FinanceToolkitCompute {
    nonisolated struct BudgetCategory: Sendable {
        let id: String
        let name: String
        /// The budget as a monthly amount; nil without one or with a weekly or yearly one.
        let monthlyLimit: Double?
        /// A weekly or yearly budget: left alone.
        let hasOtherPeriod: Bool
    }

    nonisolated static func budgetSuggestions(_ s: FinanceSnapshot, categories: [BudgetCategory], calendar: Calendar = .current) -> JSONValue {
        // The three whole months before this one, oldest first, as "yyyy-MM".
        let months: [String] = (1...3).reversed().compactMap { back in
            calendar.date(byAdding: .month, value: -back, to: s.now).map { String(FastDateParser.string(from: $0).prefix(7)) }
        }
        guard let first = months.first, let last = months.last else { return ["categories": []] }
        let rates = RateSnapshot()
        var spent: [String: [String: Double]] = [:]
        for tx in s.transactions where tx.type == .expense {
            let month = String(tx.date.prefix(7))
            guard month >= first, month <= last else { continue }
            spent[tx.category, default: [:]][month, default: 0] += baseAmount(tx, base: s.baseCurrency, rates: rates)
        }
        let rows: [(average: Double, value: JSONValue)] = categories.compactMap { category in
            let byMonth = months.map { spent[category.name]?[$0] ?? 0 }
            let average = byMonth.reduce(0, +) / Double(months.count)
            guard average > 0 || category.monthlyLimit != nil else { return nil }
            let over = category.monthlyLimit.map { limit in byMonth.filter { $0 > limit }.count }
            return (average, [
                "category_id": .string(category.id),
                "category": .string(category.name),
                "months": .array(zip(months, byMonth).map { ["month": .string($0), "spent": .number(round2($1))] }),
                "average": .number(round2(average)),
                "highest": .number(round2(byMonth.max() ?? 0)),
                "limit": category.monthlyLimit.map { JSONValue.number(round2($0)) } ?? .null,
                "months_over": over.map { JSONValue.number(Double($0)) } ?? .null,
                "other_period": .bool(category.hasOtherPeriod),
            ])
        }
        return [
            "currency": .string(s.baseCurrency),
            "from": .string("\(first)-01"),
            "months_counted": .number(Double(months.count)),
            "categories": .array(rows.sorted { $0.average > $1.average }.map(\.value)),
        ]
    }
}
