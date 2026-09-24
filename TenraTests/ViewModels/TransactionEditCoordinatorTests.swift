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
        for _ in 0..<2000 where !succeeded && editor.errorMessage == nil && editor.bulkCategoryProposal == nil {
            await Task.yield()
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
        for _ in 0..<2000 where edit.bulkCategoryProposal == nil && edit.errorMessage == nil {
            await Task.yield()
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
