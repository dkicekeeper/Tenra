//
//  AgentDrafts.swift
//  Tenra
//
//  What the assistant prepares to write (docs/plan-ai-assistant.md §3.1, "write only through a
//  draft"). A draft tool resolves the model's operations against the user's accounts and
//  categories and files them here under a draft id; nothing is saved until the person taps
//  Save on the confirm card. Saving goes through the app's own write paths
//  (`TransactionDraftService.commit` for income and expenses, `TransactionStore.add` with the
//  transfer fields of `TransactionConversion` for transfers, `CategoriesViewModel.setBudget`
//  for budgets, `SubscriptionCreationService.create` for subscriptions and regular payments),
//  and Undo takes back what was saved: deletes the transactions or the series with what it
//  generated, puts the previous budget back.
//
//  Before Save the person can change an income or an expense on the card (the voice
//  confirmation form, AgentDraftEditor); the next question tells the model what the draft
//  holds now (`<draft_status>`, AssistantViewModel).
//
//  Drafts live in memory while the app runs; a new chat clears them. A thread kept across
//  launches (AgentThreadStore) comes back without its drafts: their cards show nothing.
//

import Foundation
import Observation

/// One operation of a draft.
enum AgentDraftOperation: Equatable {
    /// Income or expense, resolved by `TransactionDraftService.makeDraft`.
    case single(TransactionDraft)
    case transfer(AgentTransferDraft)
    case budget(AgentBudgetDraft)
    case recurring(AgentRecurringDraft)
}

/// A subscription or a regular payment, as the series it will become (it starts on its next
/// charge).
struct AgentRecurringDraft: Equatable {
    var series: RecurringSeries
    /// The account was not named: the card says so.
    var accountGuessed = false
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

/// A new or changed budget of an expense category (amounts in the base currency, as budgets
/// are kept).
struct AgentBudgetDraft: Equatable {
    var categoryId: String
    var amount: Double
    var period: CustomCategory.BudgetPeriod
    /// The budget before, for the card and for Undo; nil when the category had none.
    var previousAmount: Double?
    var previousPeriod: CustomCategory.BudgetPeriod
}

/// What saving an operation wrote, for Undo.
enum AgentSavedRecord: Equatable {
    case transaction(Transaction)
    case budget(AgentBudgetDraft)
    /// A series id.
    case series(String)
}

enum AgentDraftError: Error {
    /// The category was deleted between the draft and Save.
    case categoryGone
}

struct AgentDraft: Equatable, Identifiable {
    let id: String
    var operations: [AgentDraftOperation]
}

enum AgentDraftState: Equatable {
    case pending
    case saving
    /// What was written, for Undo.
    case saved([AgentSavedRecord])
    case undone
    case failed
}

@Observable
final class AgentDraftBook {
    /// The app's write paths, swapped for fakes in tests.
    struct Writer {
        var save: @MainActor (AgentDraftOperation) async throws -> AgentSavedRecord
        var undo: @MainActor (AgentSavedRecord) async throws -> Void
    }

    private(set) var drafts: [String: AgentDraft] = [:]
    private(set) var states: [String: AgentDraftState] = [:]
    /// The drafts the person changed on the card.
    private(set) var edited: Set<String> = []
    /// The drafts the phone made from a message without the model (AgentFastPath), with that
    /// message, for the model to hear about.
    private(set) var madeOnPhone: [String: String] = [:]

    @ObservationIgnored private let writer: Writer
    @ObservationIgnored private var sequence = 0

    init(writer: Writer) {
        self.writer = writer
    }

    /// Files a draft and returns its id (`draft_1`, `draft_2`, … within the thread).
    /// - Parameter message: the person's message, for a draft the phone made without the model.
    func add(_ operations: [AgentDraftOperation], madeOnPhoneFrom message: String? = nil) -> String {
        sequence += 1
        let id = "draft_\(sequence)"
        drafts[id] = AgentDraft(id: id, operations: operations)
        states[id] = .pending
        if let message { madeOnPhone[id] = message }
        return id
    }

    /// Saves every operation of the draft, or none: a failure part-way deletes what was saved.
    func save(_ id: String) async {
        guard let draft = drafts[id], states[id] == .pending || states[id] == .failed else { return }
        states[id] = .saving
        var saved: [AgentSavedRecord] = []
        do {
            for operation in draft.operations {
                saved.append(try await writer.save(operation))
            }
            states[id] = .saved(saved)
        } catch {
            for record in saved.reversed() {
                try? await writer.undo(record)
            }
            states[id] = .failed
        }
    }

    /// The person changed one operation on the card. Only a draft not saved yet changes; one
    /// that failed to save is ready to try again.
    @discardableResult
    func replace(_ id: String, at index: Int, with operation: AgentDraftOperation) -> Bool {
        guard var draft = drafts[id], draft.operations.indices.contains(index),
              states[id] == .pending || states[id] == .failed else { return false }
        draft.operations[index] = operation
        drafts[id] = draft
        states[id] = .pending
        edited.insert(id)
        return true
    }

    /// Takes back what the draft saved.
    func undo(_ id: String) async {
        guard case .saved(let saved) = states[id] else { return }
        states[id] = .saving
        do {
            for record in saved.reversed() {
                try await writer.undo(record)
            }
            states[id] = .undone
        } catch {
            states[id] = .saved(saved)
        }
    }

    /// A kept thread came back: new drafts number on from its last one, so a draft id in its
    /// history never names a new draft.
    func continueNumbering(after last: Int) {
        sequence = max(sequence, last)
    }

    /// A new chat: the drafts go with the thread.
    func clear() {
        drafts = [:]
        states = [:]
        edited = []
        madeOnPhone = [:]
        sequence = 0
    }
}

extension AgentDraftBook.Writer {
    /// Writes as the rest of the app does: the voice and Siri path for income and expenses,
    /// the store's transfer for transfers, the categories' budget call for budgets. Undo
    /// deletes a transaction as it is now (it may have been edited since) and puts the
    /// previous budget back.
    static func app(store: TransactionStore, categoriesViewModel: CategoriesViewModel) -> Self {
        Self(
            save: { operation in
                switch operation {
                case .single(let draft):
                    return .transaction(try await TransactionDraftService.commit(draft, store: store, categoriesViewModel: categoriesViewModel))
                case .budget(let budget):
                    guard let category = store.categoryById[budget.categoryId] else { throw AgentDraftError.categoryGone }
                    categoriesViewModel.setBudget(for: budget.categoryId, amount: budget.amount, period: budget.period, resetDay: category.budgetResetDay)
                    return .budget(budget)
                case .recurring(let recurring):
                    try await SubscriptionCreationService.create(recurring.series, store: store, categoriesViewModel: categoriesViewModel)
                    return .series(recurring.series.id)
                case .transfer(let transfer):
                    return .transaction(try await store.add(Transaction(
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
                    )))
                }
            },
            undo: { record in
                switch record {
                case .transaction(let transaction):
                    guard let current = store.transactionById[transaction.id] else { return }
                    try await store.delete(current)
                case .series(let id):
                    guard store.recurringSeries.contains(where: { $0.id == id }) else { return }
                    try await store.deleteSeries(id: id, deleteTransactions: true)
                case .budget(let budget):
                    guard let category = store.categoryById[budget.categoryId] else { return }
                    if let previous = budget.previousAmount {
                        categoriesViewModel.setBudget(for: budget.categoryId, amount: previous, period: budget.previousPeriod, resetDay: category.budgetResetDay)
                    } else {
                        categoriesViewModel.removeBudget(for: budget.categoryId)
                    }
                }
            }
        )
    }
}
