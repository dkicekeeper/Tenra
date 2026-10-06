//
//  TransactionEditCoordinatorTests.swift
//  TenraTests
//
//  Characterizes the edit-transaction flow, which had no tests: amount edits,
//  the category requirement, editing after a category rename (plan 006), and
//  the "apply to similar transactions" proposal (plan 003).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized)
struct TransactionEditCoordinatorTests {

    private func add(_ graph: TransactionFlowTestGraph, _ id: String, category: String = "Food",
                     description: String = "MAGNUM", amount: Double = 1500) async throws -> Transaction {
        try await graph.store.add(Transaction(
            id: id, date: "2026-09-01", description: description, amount: amount, currency: "KZT",
            type: .expense, category: category, accountId: "a1"
        ))
    }

    private func editor(_ graph: TransactionFlowTestGraph, _ transaction: Transaction) -> TransactionEditCoordinator {
        TransactionEditCoordinator(
            transaction: transaction,
            transactionsViewModel: graph.transactions,
            categoriesViewModel: graph.categories,
            accountsViewModel: graph.accounts,
            transactionStore: graph.store
        )
    }

    /// `save` finishes on a spawned Task; wait until it reports success, an error,
    /// or a bulk-category proposal.
    private func saveAndWait(_ editor: TransactionEditCoordinator) async -> Bool {
        var succeeded = false
        editor.save { succeeded = true }
        // Bounded by time, not by a count of yields: a rate lookup runs off the main actor,
        // and on a loaded CI simulator 2000 yields ran out before its error arrived.
        let deadline = ContinuousClock.now + .seconds(30)
        while !succeeded && editor.errorMessage == nil && editor.bulkCategoryProposal == nil
                && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return succeeded
    }

    @Test func amountEditIsSaved() async throws {
        let graph = await TransactionFlowTestGraph.make()
        let original = try await add(graph, "t1")
        let edit = editor(graph, original)
        edit.formData.amountText = "2500"

        let succeeded = await saveAndWait(edit)

        #expect(succeeded)
        #expect(edit.errorMessage == nil)
        #expect(graph.store.transactionById["t1"]?.amount == 2500)
    }

    @Test func expenseWithoutCategoryCannotBeSaved() async throws {
        let graph = await TransactionFlowTestGraph.make()
        let edit = editor(graph, try await add(graph, "t1"))
        edit.formData.selectedCategory = ""
        #expect(!edit.canSave)
    }

    @Test func oldTransactionIsEditableAfterCategoryRename() async throws {
        let graph = await TransactionFlowTestGraph.make()
        _ = try await add(graph, "t1")
        var food = try #require(graph.store.categories.first { $0.name == "Food" })
        food.name = "Dining"
        graph.store.updateCategory(food)

        let current = try #require(graph.store.transactionById["t1"])
        let edit = editor(graph, current)
        edit.formData.amountText = "900"
        let succeeded = await saveAndWait(edit)

        #expect(succeeded, "error: \(edit.errorMessage ?? "none")")
        #expect(graph.store.transactionById["t1"]?.category == "Dining")
        #expect(graph.store.transactionById["t1"]?.amount == 900)
    }

    /// Making a saved one-off recurring left two transactions on its date: the series'
    /// generator added occurrence 0 on that date, then the edited transaction was linked
    /// to the same series. The edited transaction is now that first occurrence.
    @Test func makingOneOffRecurringKeepsOneTransactionOnItsDate() async throws {
        let graph = await TransactionFlowTestGraph.make()
        let today = DateFormatters.dateFormatter.string(from: Date())
        let original = try await graph.store.add(Transaction(
            id: "t1", date: today, description: "Gym", amount: 5000, currency: "KZT",
            type: .expense, category: "Food", accountId: "a1"
        ))
        graph.store.addSubcategory(Subcategory(id: "s1", name: "Membership"))
        graph.categories.linkSubcategoriesToTransaction(transactionId: "t1", subcategoryIds: ["s1"])

        let edit = editor(graph, original)
        edit.formData.amountText = "5000"
        edit.formData.recurring = .frequency(.monthly)
        let succeeded = await saveAndWait(edit)

        #expect(succeeded, "error: \(edit.errorMessage ?? "none")")
        #expect(graph.store.recurringSeries.count == 1)
        let series = try #require(graph.store.recurringSeries.first)
        let onItsDate = graph.store.transactions.filter { $0.date == today }.map(\.id)
        #expect(onItsDate == ["t1"], "the edited transaction is the first occurrence, not joined by a generated copy")
        #expect(graph.store.transactionById["t1"]?.recurringSeriesId == series.id)
        let linked = graph.store.transactions.filter { $0.recurringSeriesId == series.id }
        #expect(linked.count == 2, "the edited transaction plus the next occurrence")
        // Red Flag 5: its subcategory survives, and the generated occurrence gets it too.
        #expect(graph.store.subcategoryIdsByTransactionId["t1"] == ["s1"])
        for tx in linked where tx.id != "t1" {
            #expect(graph.store.subcategoryIdsByTransactionId[tx.id] == ["s1"])
        }
    }

    @Test func categoryChangeProposesSameMerchantTransactions() async throws {
        let graph = await TransactionFlowTestGraph.make()
        let first = try await add(graph, "t1", category: "")
        _ = try await add(graph, "t2", category: "", description: "Magnum-02")
        _ = try await add(graph, "t3", category: "", description: "MAGNUM")
        _ = try await add(graph, "other", category: "", description: "GALMART")

        let edit = editor(graph, first)
        edit.formData.selectedCategory = "Groceries"
        var dismissed = false
        edit.save { dismissed = true }
        let deadline = ContinuousClock.now + .seconds(30)
        while edit.bulkCategoryProposal == nil && edit.errorMessage == nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(!dismissed, "the sheet stays open until the user answers")
        let proposal = try #require(edit.bulkCategoryProposal)
        #expect(Set(proposal.transactionIds) == ["t2", "t3"])
        #expect(proposal.newCategory == "Groceries")

        await edit.applyBulkCategory(proposal)

        #expect(dismissed, "answering the prompt closes the sheet")
        #expect(edit.bulkCategoryProposal == nil)
        #expect(graph.store.transactionById["t2"]?.category == "Groceries")
        #expect(graph.store.transactionById["t3"]?.category == "Groceries")
        #expect(graph.store.transactionById["other"]?.category == "")
    }
}
