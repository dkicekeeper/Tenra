//
//  FinanceToolkit+Changes.swift
//  Tenra
//
//  The assistant changes what is already saved (docs/plan-ten-agent.md stage 2,
//  docs/domains/assistant.md §3): `draft_transaction_edit` prepares a change to one income or
//  expense (amount, category, date, note) and `draft_transaction_delete` the deletion of up to
//  twenty, both as drafts the person confirms on a card that shows what is there now and what
//  it becomes. `draft_recategorize` moves every record of a merchant (up to fifty) to another
//  category in one draft. Ids come from `search_transactions`. A transfer, a record of a loan or a
//  deposit and deposit interest are refused: they are changed on their own screens, where
//  their balances and schedules are kept right. A record of a recurring series is changed
//  alone; the series is never touched (CLAUDE.md red flag 10).
//

import Foundation

/// A saved income or expense as it is and as it will be.
struct AgentTransactionEdit: Equatable {
    var before: Transaction
    var after: Transaction
}

extension FinanceToolkit {
    /// The most records one delete draft takes: the card lists every one of them.
    static let deleteLimit = 20

    private struct EditInput: Decodable {
        let transactionId: String
        let amount: Double?
        let category: String?
        let date: String?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case amount, category, date, note
            case transactionId = "transaction_id"
        }
    }

    private struct DeleteInput: Decodable {
        let transactionIds: [String]

        enum CodingKeys: String, CodingKey {
            case transactionIds = "transaction_ids"
        }
    }

    /// The record by id, when the assistant may change it: an income or an expense on an
    /// everyday account. Anything else throws what to tell the user.
    private func changeable(_ id: String) throws -> Transaction {
        // The index first; the list only for an id it does not know (rare: a wrong id).
        guard let transaction = store.transactionById[id] ?? store.transactions.first(where: { $0.id == id }) else {
            throw FinanceToolError(message: "Unknown transaction \(id). Use an id from search_transactions.")
        }
        guard transaction.type == .expense || transaction.type == .income else {
            throw FinanceToolError(message: "The record of \(transaction.date) is not a plain income or expense (a transfer, a loan or a deposit record): it is changed in History, on its own screen. Offer an open block to the history.")
        }
        if let accountId = transaction.accountId, let account = store.accounts.first(where: { $0.id == accountId }),
           account.isLoan || account.isDeposit {
            throw FinanceToolError(message: "The record of \(transaction.date) belongs to a loan or a deposit: it is changed on that account's screen. Offer an open block to the account.")
        }
        return transaction
    }

    /// `draft_transaction_edit`: one income or expense with a new amount, category, date or
    /// note. The amount changes only where the record is in its account's currency (no stored
    /// conversion to recompute).
    func draftTransactionEdit(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_transaction_edit")) }
        let args = try input.decoded(as: EditInput.self)
        let before = try changeable(args.transactionId)

        var amount = before.amount
        if let given = args.amount {
            guard given.isFinite, given > 0 else { throw FinanceToolError(message: "amount must be positive.") }
            guard before.convertedAmount == nil else {
                throw FinanceToolError(message: "This record is in another currency than its account: its amount is changed in History. Offer an open block to the history.")
            }
            amount = FinanceToolkitCompute.round2(given)
        }

        var category = before.category
        if let reference = args.category?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty {
            let sameType = store.categories.filter { $0.type == before.type }
            guard let found = sameType.first(where: { $0.id == reference })
                ?? sameType.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
                throw FinanceToolError(message: "Unknown \(before.type.rawValue) category \(reference). Use a category id from <app_context>.")
            }
            category = found.name
        }

        var date = before.date
        if let given = args.date {
            guard FastDateParser.date(from: given) != nil else { throw FinanceToolError(message: "date must be YYYY-MM-DD.") }
            guard given <= FastDateParser.string(from: now()) else { throw FinanceToolError(message: "date cannot be in the future.") }
            date = given
        }

        let note = args.note.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? before.description

        let after = Transaction(
            id: before.id,
            date: date,
            description: note,
            amount: amount,
            currency: before.currency,
            convertedAmount: before.convertedAmount,
            type: before.type,
            category: category,
            // A subcategory belongs to its category: a new category drops it.
            subcategory: category == before.category ? before.subcategory : nil,
            accountId: before.accountId,
            targetAccountId: before.targetAccountId,
            accountName: before.accountName,
            targetAccountName: before.targetAccountName,
            targetCurrency: before.targetCurrency,
            targetAmount: before.targetAmount,
            recurringSeriesId: before.recurringSeriesId,
            recurringOccurrenceId: before.recurringOccurrenceId,
            createdAt: before.createdAt
        )
        guard after != before else {
            throw FinanceToolError(message: "Nothing changes: give a new amount, category, date or note.")
        }
        let id = drafts.add([.transactionEdit(AgentTransactionEdit(before: before, after: after))])
        return .success([
            "draft_id": .string(id),
            "transaction_id": .string(before.id),
            "before": Self.summary(of: before),
            "after": Self.summary(of: after),
            "saved": false,
        ])
    }

    /// `draft_transaction_delete`: up to twenty incomes or expenses to delete, one draft. A
    /// record that cannot be deleted here comes back under `skipped` with the reason.
    func draftTransactionDelete(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_transaction_delete")) }
        let args = try input.decoded(as: DeleteInput.self)
        var seen: Set<String> = []
        let ids = args.transactionIds.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { throw FinanceToolError(message: "transaction_ids must not be empty.") }
        guard ids.count <= Self.deleteLimit else {
            throw FinanceToolError(message: "At most \(Self.deleteLimit) records in one draft. Draft the first \(Self.deleteLimit), or point the user to History for a larger clean-up.")
        }
        var operations: [AgentDraftOperation] = []
        var items: [JSONValue] = []
        var skipped: [JSONValue] = []
        for id in ids {
            do {
                let transaction = try changeable(id)
                operations.append(.transactionDelete(transaction))
                items.append(Self.summary(of: transaction))
            } catch let error as FinanceToolError {
                skipped.append(["transaction_id": .string(id), "reason": .string(error.message)])
            }
        }
        guard !operations.isEmpty else {
            let reasons = skipped.compactMap { $0["reason"]?.stringValue }.joined(separator: "; ")
            return .failure("Nothing could be drafted: \(reasons)")
        }
        let id = drafts.add(operations)
        return .success([
            "draft_id": .string(id),
            "count": .number(Double(operations.count)),
            "items": .array(items),
            "skipped": .array(skipped),
            "saved": false,
        ])
    }

    /// The most records one recategorize draft moves: each is saved with its own update.
    static let recategorizeLimit = 50

    private struct RecategorizeInput: Decodable {
        let merchant: String
        let category: String
        let from: String?
        let to: String?
    }

    /// `draft_recategorize`: every income or expense whose merchant holds the given text, in a
    /// period if one is given, moved to one category, as one draft of edits. The sweep over the
    /// history runs off the main actor.
    func draftRecategorize(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_recategorize")) }
        let args = try input.decoded(as: RecategorizeInput.self)
        let needle = args.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { throw FinanceToolError(message: "merchant must be at least two characters of the merchant's name.") }
        let reference = args.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let categories = store.categories.filter { $0.type == .expense || $0.type == .income }
        guard let target = categories.first(where: { $0.id == reference })
            ?? categories.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown category \(reference). Use a category id from <app_context>.")
        }
        for day in [args.from, args.to].compactMap({ $0 }) where FastDateParser.date(from: day) == nil {
            throw FinanceToolError(message: "from and to must be YYYY-MM-DD.")
        }
        let from = args.from ?? "0000-00-00"
        let to = args.to ?? FastDateParser.string(from: now())
        let all = store.transactions
        let special = Set(store.accounts.filter { $0.isLoan || $0.isDeposit }.map(\.id))
        let type = target.type
        let name = target.name
        let found = await Task.detached(priority: .userInitiated) {
            all.filter { transaction in
                transaction.type == type && transaction.category != name
                    && transaction.date >= from && transaction.date <= to
                    && !(transaction.accountId.map(special.contains) ?? false)
                    && transaction.description.lowercased().contains(needle)
            }
        }.value
        guard !found.isEmpty else {
            return .failure("No \(type.rawValue) records with \(args.merchant) outside \(name) in that period. Check the merchant's spelling with search_transactions.")
        }
        guard found.count <= Self.recategorizeLimit else {
            throw FinanceToolError(message: "\(found.count) records match: at most \(Self.recategorizeLimit) in one draft. Narrow the period with from and to (for example one month at a time).")
        }
        let operations: [AgentDraftOperation] = found.map { before in
            .transactionEdit(AgentTransactionEdit(before: before, after: Self.moved(before, to: name)))
        }
        let id = drafts.add(operations)
        return .success([
            "draft_id": .string(id),
            "count": .number(Double(found.count)),
            "category_id": .string(target.id),
            "category": .string(name),
            "from_categories": .array(Set(found.map(\.category)).sorted().map(JSONValue.string)),
            "first": Self.summary(of: found[0]),
            "saved": false,
        ])
    }

    /// The record in another category: its subcategory belongs to the old one and goes.
    private static func moved(_ before: Transaction, to category: String) -> Transaction {
        Transaction(
            id: before.id,
            date: before.date,
            description: before.description,
            amount: before.amount,
            currency: before.currency,
            convertedAmount: before.convertedAmount,
            type: before.type,
            category: category,
            subcategory: nil,
            accountId: before.accountId,
            targetAccountId: before.targetAccountId,
            accountName: before.accountName,
            targetAccountName: before.targetAccountName,
            targetCurrency: before.targetCurrency,
            targetAmount: before.targetAmount,
            recurringSeriesId: before.recurringSeriesId,
            recurringOccurrenceId: before.recurringOccurrenceId,
            createdAt: before.createdAt
        )
    }

    /// A record in a tool result: what it is, never its account's balance.
    private static func summary(of transaction: Transaction) -> JSONValue {
        [
            "transaction_id": .string(transaction.id),
            "date": .string(transaction.date),
            "type": .string(transaction.type.rawValue),
            "amount": .number(FinanceToolkitCompute.round2(transaction.amount)),
            "currency": .string(transaction.currency),
            "category": .string(transaction.category),
            "merchant": .string(transaction.description),
        ]
    }

    /// What an edit or a delete draft will do (FinanceToolkit.describe).
    func describeChange(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .transactionEdit(let edit):
            return ["type": "transaction_edit", "before": Self.summary(of: edit.before), "after": Self.summary(of: edit.after)]
        case .transactionDelete(let transaction):
            return ["type": "transaction_delete", "record": Self.summary(of: transaction)]
        default:
            return .null
        }
    }
}
