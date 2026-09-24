//
//  ImportCommitPlanner.swift
//  Tenra
//
//  Turns the review screen's per-row decisions into store operations, and runs
//  them. Split from the view so the three outcomes a row can have are testable:
//
//   • a plain expense/income on the statement's account (with subcategories);
//   • a transfer between the statement's account and another of the user's
//     accounts ("Перевод · Асан Б., Freedom Bank" marked as Kaspi → Freedom);
//   • the second side of a transfer already in Tenra as a plain expense/income
//     on the other account: that transaction becomes the transfer and the row is
//     not added (ImportTransferMatcher's counterpart match).
//

import Foundation

/// What the review screen decided for one selected row.
struct ImportRowDecision: Sendable {
    /// The row as recognized (positive amount, direction in `type`).
    let row: Transaction
    /// The statement's account this row belongs to.
    let accountId: String
    /// Savable category ("" = uncategorized). Ignored for transfers.
    let category: String
    let subcategoryIds: [String]
    /// The user's other account, when the row is a transfer between own accounts.
    let transferAccountId: String?
    /// A saved expense/income on `transferAccountId` that is the other side of
    /// this transfer; it is converted instead of adding the row.
    let mergeWith: Transaction?
}

enum ImportOperation: Sendable, Equatable {
    case add(Transaction, subcategoryIds: [String])
    /// Replace `old` with `new` (same id). `statementAccountId` is the account whose
    /// balance the conversion newly moves; the other leg was already counted.
    case convert(old: Transaction, new: Transaction, statementAccountId: String)
}

nonisolated enum ImportCommitPlanner {

    static func operations(for decisions: [ImportRowDecision]) -> [ImportOperation] {
        decisions.map { decision in
            let row = decision.row
            let isMovement = row.type == .expense || row.type == .income
            guard isMovement,
                  let other = decision.transferAccountId, !other.isEmpty, other != decision.accountId else {
                return .add(plain(decision), subcategoryIds: decision.subcategoryIds)
            }
            let outgoing = row.type == .expense

            if let existing = decision.mergeWith, existing.accountId == other {
                let converted = transfer(
                    id: existing.id,
                    date: existing.date,
                    description: existing.description,
                    source: outgoing ? decision.accountId : other,
                    target: outgoing ? other : decision.accountId,
                    sourceAmount: outgoing ? row.amount : existing.amount,
                    sourceCurrency: outgoing ? row.currency : existing.currency,
                    targetAmount: outgoing ? existing.amount : row.amount,
                    targetCurrency: outgoing ? existing.currency : row.currency,
                    createdAt: existing.createdAt
                )
                return .convert(old: existing, new: converted, statementAccountId: decision.accountId)
            }

            return .add(transfer(
                id: row.id,
                date: row.date,
                description: row.description,
                source: outgoing ? decision.accountId : other,
                target: outgoing ? other : decision.accountId,
                sourceAmount: row.amount,
                sourceCurrency: row.currency,
                targetAmount: row.amount,
                targetCurrency: row.currency,
                createdAt: row.createdAt
            ), subcategoryIds: [])
        }
    }

    private static func plain(_ decision: ImportRowDecision) -> Transaction {
        let row = decision.row
        return Transaction(
            id: row.id,
            date: row.date,
            description: row.description,
            amount: row.amount,
            currency: row.currency,
            convertedAmount: row.convertedAmount,
            type: row.type,
            category: row.type == .expense || row.type == .income ? decision.category : row.category,
            subcategory: row.subcategory,
            accountId: decision.accountId,
            targetAccountId: row.targetAccountId,
            recurringSeriesId: row.recurringSeriesId,
            recurringOccurrenceId: row.recurringOccurrenceId,
            createdAt: row.createdAt
        )
    }

    private static func transfer(
        id: String, date: String, description: String,
        source: String, target: String,
        sourceAmount: Double, sourceCurrency: String,
        targetAmount: Double, targetCurrency: String,
        createdAt: TimeInterval
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: sourceAmount,
            currency: sourceCurrency,
            type: .internalTransfer,
            category: TransactionType.transferCategoryName,
            accountId: source,
            targetAccountId: target,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount,
            createdAt: createdAt
        )
    }
}

@MainActor
enum ImportCommitter {

    /// Runs `operations` in order and returns how many rows were saved (added or
    /// converted). A row the store rejects is skipped, as before. Subcategory links
    /// are written in one batch; rows dated before their account's creation keep the
    /// balance the user entered (ImportBalanceCompensation).
    @discardableResult
    static func commit(
        _ operations: [ImportOperation],
        store: TransactionStore,
        categories: CategoriesViewModel?,
        balance: BalanceCoordinator?
    ) async -> Int {
        var added: [Transaction] = []
        var convertedLegs: [(transaction: Transaction, accountId: String)] = []
        var links: [String: [String]] = [:]

        for operation in operations {
            switch operation {
            case .add(let transaction, let subcategoryIds):
                guard let saved = try? await store.add(transaction) else { continue }
                added.append(saved)
                if !subcategoryIds.isEmpty {
                    links[saved.id] = subcategoryIds
                    linkToCategory(subcategoryIds, category: saved.category, type: saved.type,
                                   store: store, categories: categories)
                }
            case .convert(_, let new, let statementAccountId):
                guard (try? await store.update(new)) != nil else { continue }
                convertedLegs.append((new, statementAccountId))
                // Transfers carry no subcategories.
                if !(store.subcategoryIdsByTransactionId[new.id]?.isEmpty ?? true) {
                    links[new.id] = []
                }
            }
        }

        if !links.isEmpty {
            categories?.batchLinkSubcategoriesToTransaction(links)
        }
        if let balance {
            await ImportBalanceCompensation.apply(saved: added, convertedLegs: convertedLegs,
                                                  store: store, coordinator: balance)
        }
        return added.count + convertedLegs.count
    }

    /// Joins each tag to the category's carousel. The category is resolved by name AND
    /// type (categories.md: `categoryIdByName` collides across types).
    private static func linkToCategory(
        _ subcategoryIds: [String], category: String, type: TransactionType,
        store: TransactionStore, categories: CategoriesViewModel?
    ) {
        guard let categories,
              let categoryId = store.categories.first(where: { $0.name == category && $0.type == type })?.id
        else { return }
        let linked = Set(store.subcategoryIdsByCategoryId[categoryId] ?? [])
        for id in subcategoryIds where !linked.contains(id) {
            categories.linkSubcategoryToCategory(subcategoryId: id, categoryId: categoryId)
        }
    }
}
