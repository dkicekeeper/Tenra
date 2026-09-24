//
//  TransactionAddCoordinatorTests.swift
//  TenraTests
//
//  Characterizes the main add-transaction flow, which had no tests: validation,
//  the saved transaction, the recurring branch, and the rating-prompt counter
//  (the counter bug fixed on 2026-09-24 lived here unnoticed).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct TransactionAddCoordinatorTests {

    private func coordinator(_ graph: TransactionFlowTestGraph, category: String = "Food") -> TransactionAddCoordinator {
        TransactionAddCoordinator(
            category: category,
            type: .expense,
            currency: "KZT",
            transactionsViewModel: graph.transactions,
            categoriesViewModel: graph.categories,
            accountsViewModel: graph.accounts,
            transactionStore: graph.store
        )
    }

    @Test func validExpenseIsSavedAndCounted() async {
        let graph = await TransactionFlowTestGraph.make()
        let add = coordinator(graph)
        add.formData.amountText = "1500"
        add.formData.accountId = "a1"
        let countBefore = TransactionFlowTestGraph.ratingTxCount

        let result = await add.save()

        #expect(result.isValid)
        #expect(graph.store.transactions.count == 1)
        let saved = graph.store.transactions.first
        #expect(saved?.amount == 1500)
        #expect(saved?.category == "Food")
        #expect(saved?.accountId == "a1")
        #expect(saved?.type == .expense)
        #expect(TransactionFlowTestGraph.ratingTxCount == countBefore + 1)
    }

    @Test func emptyAmountIsRejected() async {
        let graph = await TransactionFlowTestGraph.make()
        let add = coordinator(graph)
        add.formData.amountText = ""
        add.formData.accountId = "a1"

        let result = await add.save()

        #expect(!result.isValid)
        #expect(graph.store.transactions.isEmpty)
    }

    @Test func missingAccountIsRejected() async {
        let graph = await TransactionFlowTestGraph.make()
        let add = coordinator(graph)
        add.formData.amountText = "1500"
        add.formData.accountId = nil

        let result = await add.save()

        #expect(!result.isValid)
        if case .accountNotSelected = result.errors.first {} else {
            Issue.record("expected accountNotSelected, got \(result.errors)")
        }
    }

    @Test func unknownAccountIsRejected() async {
        let graph = await TransactionFlowTestGraph.make()
        let add = coordinator(graph)
        add.formData.amountText = "1500"
        add.formData.accountId = "missing"

        let result = await add.save()

        if case .accountNotFound = result.errors.first {} else {
            Issue.record("expected accountNotFound, got \(result.errors)")
        }
    }

    @Test func recurringMonthlyCreatesSeriesAndCountsOnce() async {
        let graph = await TransactionFlowTestGraph.make()
        let add = coordinator(graph)
        add.formData.amountText = "4990"
        add.formData.accountId = "a1"
        add.formData.recurring = .frequency(.monthly)
        let countBefore = TransactionFlowTestGraph.ratingTxCount

        let result = await add.save()

        #expect(result.isValid)
        #expect(graph.store.recurringStore.recurringSeries.count == 1)
        #expect(graph.store.transactions.contains { $0.recurringSeriesId != nil })
        #expect(TransactionFlowTestGraph.ratingTxCount == countBefore + 1)
    }
}
