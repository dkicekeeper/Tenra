//
//  TransactionEvent.swift
//  Tenra
//
//  Created on 2026-02-05
//  Refactoring Phase 0: Event Sourcing Model
//

import Foundation

/// One row of a `.bulkUpdated` event: the stored transaction and what replaces it.
struct TransactionChange: Equatable, Sendable {
    let old: Transaction
    let new: Transaction
}

/// Event representing a transaction state change
/// Used for event sourcing pattern - all transaction modifications go through events
enum TransactionEvent {
    // MARK: - Transaction Events
    case added(Transaction)
    case updated(old: Transaction, new: Transaction)
    case deleted(Transaction)
    case bulkAdded([Transaction])
    /// Several existing transactions edited at once ("apply to similar", linking or
    /// unlinking a series' payments, detaching a deleted series). Same index maintenance as
    /// `.updated` per row, but one pass over the arrays, one balance recalculation for the
    /// touched accounts and one CoreData save. See TransactionStore+BulkMutations.swift.
    case bulkUpdated([TransactionChange])
    /// Several transactions deleted at once (an account's or a category's transactions, a
    /// series' occurrences). Must not carry a payment to a loan that still exists: those go
    /// through `.deleted`, which rolls the loan back (`deleteTransactionsInBulk` splits them).
    case bulkDeleted([Transaction])

    // MARK: - Recurring Series Events (Phase 9: Aggressive Integration)
    case seriesCreated(RecurringSeries)
    case seriesUpdated(old: RecurringSeries, new: RecurringSeries)
    case seriesStopped(seriesId: String, fromDate: String)
    case seriesDeleted(seriesId: String, deleteTransactions: Bool)

    // MARK: - Computed Properties

    /// Account IDs affected by this event
    /// Used to determine which account balances need recalculation
    var affectedAccounts: Set<String> {
        switch self {
        case .added(let tx):
            return accountIds(from: tx)

        case .updated(let old, let new):
            var ids = accountIds(from: old)
            ids.formUnion(accountIds(from: new))
            return ids

        case .deleted(let tx):
            return accountIds(from: tx)

        case .bulkAdded(let transactions):
            return Set(transactions.flatMap { accountIds(from: $0) })

        case .bulkUpdated(let changes):
            var ids = Set<String>()
            for change in changes {
                ids.formUnion(accountIds(from: change.old))
                ids.formUnion(accountIds(from: change.new))
            }
            return ids

        case .bulkDeleted(let transactions):
            return Set(transactions.flatMap { accountIds(from: $0) })

        // MARK: - Recurring Series Events (Phase 9)
        case .seriesCreated(let series):
            // Series creation generates transactions → will affect account balances
            return series.accountId.map { Set([$0]) } ?? Set()

        case .seriesUpdated(let old, let new):
            // May regenerate transactions → potentially affects accounts
            var ids = Set<String>()
            if let accountId = old.accountId {
                ids.insert(accountId)
            }
            if let accountId = new.accountId {
                ids.insert(accountId)
            }
            return ids

        case .seriesStopped(_, _):
            // Stopping series deletes future transactions → affects balances
            // Account IDs will be determined during processing
            return Set()

        case .seriesDeleted(_, _):
            // Deleting series may delete/convert transactions → affects balances
            // Account IDs will be determined during processing
            return Set()
        }
    }

    /// Category names affected by this event
    /// Used to determine which category aggregates need recalculation
    var affectedCategories: Set<String> {
        switch self {
        case .added(let tx):
            return Set([tx.category].compactMap { $0.isEmpty ? nil : $0 })

        case .updated(let old, let new):
            var categories = Set<String>()
            if !old.category.isEmpty {
                categories.insert(old.category)
            }
            if !new.category.isEmpty {
                categories.insert(new.category)
            }
            return categories

        case .deleted(let tx):
            return Set([tx.category].compactMap { $0.isEmpty ? nil : $0 })

        case .bulkAdded(let transactions):
            return Set(transactions.map { $0.category }.filter { !$0.isEmpty })

        case .bulkUpdated(let changes):
            return Set(changes.flatMap { [$0.old.category, $0.new.category] }.filter { !$0.isEmpty })

        case .bulkDeleted(let transactions):
            return Set(transactions.map { $0.category }.filter { !$0.isEmpty })

        case .seriesCreated(let series):
            return series.category.isEmpty ? Set() : Set([series.category])

        case .seriesUpdated(let old, let new):
            var categories = Set<String>()
            if !old.category.isEmpty {
                categories.insert(old.category)
            }
            if !new.category.isEmpty {
                categories.insert(new.category)
            }
            return categories

        case .seriesStopped:
            return Set() // No category impact for stopping

        case .seriesDeleted:
            return Set() // No category impact for deletion
        }
    }

    /// All transactions involved in this event
    var transactions: [Transaction] {
        switch self {
        case .added(let tx):
            return [tx]
        case .updated(_, let new):
            return [new]
        case .deleted(let tx):
            return [tx]
        case .bulkAdded(let txs):
            return txs
        case .bulkUpdated(let changes):
            return changes.map(\.new)
        case .bulkDeleted(let txs):
            return txs

        case .seriesCreated, .seriesUpdated, .seriesStopped, .seriesDeleted:
            return []
        }
    }

    /// Human-readable description for debugging
    var debugDescription: String {
        switch self {
        case .added(let tx):
            return "ADD: \(tx.category) \(tx.amount) \(tx.currency)"
        case .updated(let old, let new):
            return "UPDATE: \(old.id) - \(old.amount) → \(new.amount)"
        case .deleted(let tx):
            return "DELETE: \(tx.category) \(tx.amount) \(tx.currency)"
        case .bulkAdded(let txs):
            return "BULK_ADD: \(txs.count) transactions"
        case .bulkUpdated(let changes):
            return "BULK_UPDATE: \(changes.count) transactions"
        case .bulkDeleted(let txs):
            return "BULK_DELETE: \(txs.count) transactions"

        // MARK: - Recurring Series Events (Phase 9)
        case .seriesCreated(let series):
            return "SERIES_CREATED: \(series.description) (\(series.frequency.rawValue))"
        case .seriesUpdated(let old, let new):
            return "SERIES_UPDATED: \(old.id) - \(old.amount) → \(new.amount)"
        case .seriesStopped(let seriesId, let fromDate):
            return "SERIES_STOPPED: \(seriesId) from \(fromDate)"
        case .seriesDeleted(let seriesId, let deleteTransactions):
            return "SERIES_DELETED: \(seriesId), deleteTxns=\(deleteTransactions)"
        }
    }

    // MARK: - Private Helpers

    /// Extract all account IDs from a transaction
    private func accountIds(from transaction: Transaction) -> Set<String> {
        var ids = Set<String>()

        if let accountId = transaction.accountId, !accountId.isEmpty {
            ids.insert(accountId)
        }

        if let targetId = transaction.targetAccountId, !targetId.isEmpty {
            ids.insert(targetId)
        }

        return ids
    }
}

// MARK: - Equatable

extension TransactionEvent: Equatable {
    static func == (lhs: TransactionEvent, rhs: TransactionEvent) -> Bool {
        switch (lhs, rhs) {
        case (.added(let lhsTx), .added(let rhsTx)):
            return lhsTx.id == rhsTx.id

        case (.updated(let lhsOld, let lhsNew), .updated(let rhsOld, let rhsNew)):
            return lhsOld.id == rhsOld.id && lhsNew.id == rhsNew.id

        case (.deleted(let lhsTx), .deleted(let rhsTx)):
            return lhsTx.id == rhsTx.id

        case (.bulkAdded(let lhsTxs), .bulkAdded(let rhsTxs)):
            return lhsTxs.map { $0.id } == rhsTxs.map { $0.id }

        case (.bulkUpdated(let lhsChanges), .bulkUpdated(let rhsChanges)):
            return lhsChanges.map { $0.new.id } == rhsChanges.map { $0.new.id }

        case (.bulkDeleted(let lhsTxs), .bulkDeleted(let rhsTxs)):
            return lhsTxs.map { $0.id } == rhsTxs.map { $0.id }

        // MARK: - Recurring Series Events (Phase 9)
        case (.seriesCreated(let lhsSeries), .seriesCreated(let rhsSeries)):
            return lhsSeries.id == rhsSeries.id

        case (.seriesUpdated(let lhsOld, let lhsNew), .seriesUpdated(let rhsOld, let rhsNew)):
            return lhsOld.id == rhsOld.id && lhsNew.id == rhsNew.id

        case (.seriesStopped(let lhsId, let lhsDate), .seriesStopped(let rhsId, let rhsDate)):
            return lhsId == rhsId && lhsDate == rhsDate

        case (.seriesDeleted(let lhsId, let lhsDelete), .seriesDeleted(let rhsId, let rhsDelete)):
            return lhsId == rhsId && lhsDelete == rhsDelete

        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension TransactionEvent: CustomStringConvertible {
    var description: String {
        debugDescription
    }
}
