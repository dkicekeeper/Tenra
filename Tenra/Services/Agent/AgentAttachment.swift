//
//  AgentAttachment.swift
//  Tenra
//
//  A receipt or a statement attached in the assistant's chat (docs/domains/assistant.md §7).
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
        let main: String? = currencies.max { (lhs: (key: String, value: [Transaction]), rhs: (key: String, value: [Transaction])) -> Bool in
            if lhs.value.count == rhs.value.count { return lhs.key > rhs.key }
            return lhs.value.count < rhs.value.count
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
        let dates: [String] = rows.map(\.date).sorted()
        let totals: [CategoryTotal] = byCategory.map { CategoryTotal(category: $0.key, amount: $0.value) }
        let ranked: [CategoryTotal] = totals.sorted { (lhs: CategoryTotal, rhs: CategoryTotal) -> Bool in
            if lhs.amount == rhs.amount { return lhs.category < rhs.category }
            return lhs.amount > rhs.amount
        }
        let uncategorized: Int = rows.filter { review.suggestedCategories[$0.id] == nil }.count
        return Self(
            kind: .statement,
            title: accountName,
            count: rows.count,
            skipped: review.outcome.statement.skipped.count,
            firstDate: dates.first,
            lastDate: dates.last,
            expenses: total(.expense),
            income: total(.income),
            uncategorized: uncategorized,
            moves: review.uncheckedMoves.count,
            byCategory: Array(ranked.prefix(8))
        )
    }

    /// The `<attachment_result>` block: figures only, no names, numbers or counterparties from
    /// the document. Nothing in it is saved until the person reviews it.
    var modelText: String {
        func round(_ value: Double) -> JSONValue { .number(FinanceToolkitCompute.round2(value)) }
        func money(_ total: Total?) -> JSONValue {
            guard let total else { return .null }
            return .object(["amount": round(total.amount), "currency": .string(total.currency)])
        }
        let categories: [JSONValue] = byCategory.map { (item: CategoryTotal) -> JSONValue in
            .object(["category": .string(item.category), "amount": round(item.amount)])
        }
        var fields: [String: JSONValue] = [:]
        fields["kind"] = .string(kind == .receipt ? "receipt" : "statement")
        fields["rows"] = .number(Double(count))
        fields["unreadable_rows"] = .number(Double(skipped))
        fields["from"] = firstDate.map(JSONValue.string) ?? .null
        fields["to"] = lastDate.map(JSONValue.string) ?? .null
        fields["expenses"] = money(expenses)
        fields["income"] = money(income)
        fields["uncategorized_rows"] = .number(Double(uncategorized))
        fields["cash_and_own_transfers"] = .number(Double(moves))
        fields["expenses_by_category"] = .array(categories)
        fields["saved"] = .bool(false)
        return "<attachment_result>\n\(JSONValue.object(fields).jsonString())\n</attachment_result>"
    }
}
