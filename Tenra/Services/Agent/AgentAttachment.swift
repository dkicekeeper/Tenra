//
//  AgentAttachment.swift
//  Tenra
//
//  A receipt or a statement attached in the assistant's chat (docs/plan-ai-assistant.md §3.8).
//  It is read on the phone by the import pipelines (docs/domains/import.md) and never leaves it:
//  the chat shows a summary card built without the model, "Review" opens the app's own review
//  screen, and the model sees only the summary (counts, period, totals by category, flags) in an
//  `<attachment_result>` block, with the person's next question.
//

import Foundation

/// What the review screen needs.
enum AgentAttachment {
    case receipt(ReceiptDraft)
    case statement(StatementReview)
}

/// The card's figures and the model's summary.
struct AgentAttachmentSummary: Equatable {
    enum Kind: Equatable {
        case receipt
        case statement
    }

    struct Total: Equatable {
        var amount: Double
        var currency: String
    }

    struct CategoryTotal: Equatable {
        var category: String
        var amount: Double
    }

    var kind: Kind
    /// The shop on a receipt; the statement's account, when it was recognized.
    var title: String?
    var count: Int
    /// Rows the statement had that could not be read.
    var skipped: Int
    /// The period, `yyyy-MM-dd`.
    var firstDate: String?
    var lastDate: String?
    /// In the currency most rows are in.
    var expenses: Total?
    var income: Total?
    /// Rows with no category suggested yet.
    var uncategorized: Int
    /// Cash withdrawals and moves between the person's own accounts, which start unchecked.
    var moves: Int
    /// Expenses by suggested category, largest first, in the main currency.
    var byCategory: [CategoryTotal]

    static func receipt(_ draft: ReceiptDraft, baseCurrency: String) -> Self {
        let total = Total(amount: draft.total, currency: draft.currency ?? baseCurrency)
        return Self(
            kind: .receipt, title: draft.merchant.isEmpty ? nil : draft.merchant, count: 1, skipped: 0,
            firstDate: draft.date, lastDate: draft.date, expenses: total, income: nil,
            uncategorized: 0, moves: 0, byCategory: []
        )
    }

    static func statement(_ review: StatementReview, accountName: String?) -> Self {
        let rows = review.transactions.filter { $0.type == .expense || $0.type == .income }
        let currencies = Dictionary(grouping: rows, by: \.currency)
        let main = currencies.max { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key > rhs.key : lhs.value.count < rhs.value.count
        }?.key
        let inMain = rows.filter { $0.currency == main }
        func total(_ type: TransactionType) -> Total? {
            let picked = inMain.filter { $0.type == type }
            guard let main, !picked.isEmpty else { return nil }
            return Total(amount: picked.reduce(0) { $0 + $1.amount }, currency: main)
        }
        var byCategory: [String: Double] = [:]
        for row in inMain where row.type == .expense {
            guard let category = review.suggestedCategories[row.id] else { continue }
            byCategory[category, default: 0] += row.amount
        }
        let dates = rows.map(\.date).sorted()
        return Self(
            kind: .statement,
            title: accountName,
            count: rows.count,
            skipped: review.outcome.statement.skipped.count,
            firstDate: dates.first,
            lastDate: dates.last,
            expenses: total(.expense),
            income: total(.income),
            uncategorized: rows.filter { review.suggestedCategories[$0.id] == nil }.count,
            moves: review.uncheckedMoves.count,
            byCategory: byCategory
                .map { CategoryTotal(category: $0.key, amount: $0.value) }
                .sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount }
                .prefix(8)
                .map { $0 }
        )
    }

    /// The `<attachment_result>` block: figures only, no names, numbers or counterparties from
    /// the document. Nothing in it is saved until the person reviews it.
    var modelText: String {
        func round(_ value: Double) -> JSONValue { .number(FinanceToolkitCompute.round2(value)) }
        func money(_ total: Total?) -> JSONValue {
            guard let total else { return .null }
            return ["amount": round(total.amount), "currency": .string(total.currency)]
        }
        let summary: JSONValue = [
            "kind": .string(kind == .receipt ? "receipt" : "statement"),
            "rows": .number(Double(count)),
            "unreadable_rows": .number(Double(skipped)),
            "from": firstDate.map(JSONValue.string) ?? .null,
            "to": lastDate.map(JSONValue.string) ?? .null,
            "expenses": money(expenses),
            "income": money(income),
            "uncategorized_rows": .number(Double(uncategorized)),
            "cash_and_own_transfers": .number(Double(moves)),
            "expenses_by_category": .array(byCategory.map { ["category": .string($0.category), "amount": round($0.amount)] }),
            "saved": false,
        ]
        return "<attachment_result>\n\(summary.jsonString())\n</attachment_result>"
    }
}
