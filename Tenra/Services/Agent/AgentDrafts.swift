//
//  AgentDrafts.swift
//  Tenra
//
//  What the assistant prepares to write (docs/plan-ai-assistant.md §3.1, "write only through a
//  draft"). A draft tool resolves the model's operations against the user's accounts and
//  categories and files them here under a draft id; nothing is saved until the person taps
//  Save on the confirm card. Saving goes through the app's own write paths
//  (`TransactionDraftService.commit` for income and expenses, `TransactionStore.add` with the
//  transfer fields of `TransactionConversion` for transfers), and Undo deletes what was saved.
//
//  Drafts live as long as the thread does, in memory; a new chat clears them.
//

import Foundation
import Observation

/// One operation of a draft.
enum AgentDraftOperation: Equatable {
    /// Income or expense, resolved by `TransactionDraftService.makeDraft`.
    case single(TransactionDraft)
    case transfer(AgentTransferDraft)
}

struct AgentTransferDraft: Equatable {
    var fromAccountId: String
    var toAccountId: String
    var amount: Double
    var currency: String
    /// What leaves the source and what reaches the target, in their currencies.
    var conversion: TransactionConversion
    var date: Date
    var note: String
}

struct AgentDraft: Equatable, Identifiable {
    let id: String
    var operations: [AgentDraftOperation]
}

enum AgentDraftState: Equatable {
    case pending
    case saving
    /// What was written, for Undo.
    case saved([Transaction])
    case undone
    case failed
}

@Observable
final class AgentDraftBook {
    /// The app's write paths, swapped for fakes in tests.
    struct Writer {
        var save: @MainActor (AgentDraftOperation) async throws -> Transaction
        var delete: @MainActor (Transaction) async throws -> Void
    }

    private(set) var drafts: [String: AgentDraft] = [:]
    private(set) var states: [String: AgentDraftState] = [:]

    @ObservationIgnored private let writer: Writer
    @ObservationIgnored private var sequence = 0

    init(writer: Writer) {
        self.writer = writer
    }

    /// Files a draft and returns its id (`draft_1`, `draft_2`, … within the thread).
    func add(_ operations: [AgentDraftOperation]) -> String {
        sequence += 1
        let id = "draft_\(sequence)"
        drafts[id] = AgentDraft(id: id, operations: operations)
        states[id] = .pending
        return id
    }

    /// Saves every operation of the draft, or none: a failure part-way deletes what was saved.
    func save(_ id: String) async {
        guard let draft = drafts[id], states[id] == .pending || states[id] == .failed else { return }
        states[id] = .saving
        var saved: [Transaction] = []
        do {
            for operation in draft.operations {
                saved.append(try await writer.save(operation))
            }
            states[id] = .saved(saved)
        } catch {
            for transaction in saved.reversed() {
                try? await writer.delete(transaction)
            }
            states[id] = .failed
        }
    }

    /// Deletes what the draft saved.
    func undo(_ id: String) async {
        guard case .saved(let saved) = states[id] else { return }
        states[id] = .saving
        do {
            for transaction in saved.reversed() {
                try await writer.delete(transaction)
            }
            states[id] = .undone
        } catch {
            states[id] = .saved(saved)
        }
    }

    /// A new chat: the drafts go with the thread.
    func clear() {
        drafts = [:]
        states = [:]
        sequence = 0
    }
}

extension AgentDraftBook.Writer {
    /// Writes as the rest of the app does: the voice and Siri path for income and expenses,
    /// the store's transfer for transfers. Undo deletes the transaction as it is now (it may
    /// have been edited since).
    static func app(store: TransactionStore, categoriesViewModel: CategoriesViewModel) -> Self {
        Self(
            save: { operation in
                switch operation {
                case .single(let draft):
                    return try await TransactionDraftService.commit(draft, store: store, categoriesViewModel: categoriesViewModel)
                case .transfer(let transfer):
                    return try await store.add(Transaction(
                        id: "",
                        date: DateFormatters.dateFormatter.string(from: transfer.date),
                        description: transfer.note,
                        amount: transfer.amount,
                        currency: transfer.currency,
                        convertedAmount: transfer.conversion.convertedAmount,
                        type: .internalTransfer,
                        category: TransactionType.transferCategoryName,
                        accountId: transfer.fromAccountId,
                        targetAccountId: transfer.toAccountId,
                        targetCurrency: transfer.conversion.targetCurrency ?? transfer.currency,
                        targetAmount: transfer.conversion.targetAmount ?? transfer.amount
                    ))
                }
            },
            delete: { transaction in
                guard let current = store.transactionById[transaction.id] else { return }
                try await store.delete(current)
            }
        )
    }
}
