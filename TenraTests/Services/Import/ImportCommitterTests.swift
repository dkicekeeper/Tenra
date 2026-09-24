//
//  ImportCommitterTests.swift
//  TenraTests
//
//  Saving the review screen's plan against a real TransactionStore: the second
//  side of a transfer converts the saved transaction instead of adding income,
//  balances move once, and subcategory links are written.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized)
struct ImportCommitterTests {

    /// Two accounts created long before the statement rows, so balance
    /// compensation stays out of the way, each starting at 100 000.
    private func makeGraph() async -> TransactionFlowTestGraph {
        let graph = await TransactionFlowTestGraph.make()
        let created = DateFormatters.dateFormatter.date(from: "2026-01-01")!
        graph.store.accounts = [
            Account(id: "kaspi", name: "Kaspi", currency: "KZT", createdDate: created, initialBalance: 100_000),
            Account(id: "freedom", name: "Freedom", currency: "KZT", createdDate: created, initialBalance: 100_000)
        ]
        graph.store.rebuildAccountById()
        await graph.balance.registerAccounts(graph.store.accounts)
        await graph.balance.setInitialBalance(100_000, for: "kaspi")
        await graph.balance.setInitialBalance(100_000, for: "freedom")
        await graph.balance.recalculateAll(accounts: graph.store.accounts, transactions: graph.store.transactions)
        return graph
    }

    private func balance(_ graph: TransactionFlowTestGraph, _ id: String) -> Double {
        graph.balance.balances[id] ?? .nan
    }

    @Test func secondSideOfATransferMergesIntoOne() async throws {
        let graph = await makeGraph()
        let freedomSide = try await graph.store.add(Transaction(
            id: "f1", date: "2026-09-19", description: "Перевод с карты на карту", amount: 50_000,
            currency: "KZT", type: .expense, category: "", accountId: "freedom"
        ))
        #expect(abs(balance(graph, "freedom") - 50_000) < 0.5)

        let kaspiRow = Transaction(
            id: "r1", date: "2026-09-19", description: "Пополнение · С карты другого банка", amount: 50_000,
            currency: "KZT", type: .income, category: "", accountId: nil
        )
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: kaspiRow, accountId: "kaspi", category: "", subcategoryIds: [],
                              transferAccountId: "freedom", mergeWith: freedomSide)
        ])
        let saved = await ImportCommitter.commit(operations, store: graph.store,
                                                 categories: graph.categories, balance: graph.balance)

        #expect(saved == 1)
        #expect(graph.store.transactions.count == 1, "no second transaction is added")
        let transfer = try #require(graph.store.transactionById["f1"])
        #expect(transfer.type == .internalTransfer)
        #expect(transfer.accountId == "freedom" && transfer.targetAccountId == "kaspi")
        #expect(abs(balance(graph, "freedom") - 50_000) < 0.5, "the Freedom side was already counted")
        #expect(abs(balance(graph, "kaspi") - 150_000) < 0.5)
    }

    @Test func markedTransferMovesBothBalances() async throws {
        let graph = await makeGraph()
        let row = Transaction(
            id: "r1", date: "2026-09-04", description: "Перевод · Тест К., Freedom Bank", amount: 20_000,
            currency: "KZT", type: .expense, category: "", accountId: nil
        )
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: row, accountId: "kaspi", category: "", subcategoryIds: [],
                              transferAccountId: "freedom", mergeWith: nil)
        ])
        await ImportCommitter.commit(operations, store: graph.store, categories: graph.categories, balance: graph.balance)

        #expect(graph.store.transactionById["r1"]?.type == .internalTransfer)
        #expect(abs(balance(graph, "kaspi") - 80_000) < 0.5)
        #expect(abs(balance(graph, "freedom") - 120_000) < 0.5)
    }

    @Test func subcategoryIsLinkedToTheRowAndItsCategory() async throws {
        let graph = await makeGraph()
        let loved = graph.categories.addSubcategory(name: "Любимая")
        let food = try #require(graph.store.categories.first { $0.name == "Food" })

        let row = Transaction(
            id: "r1", date: "2026-09-19", description: "Перевод · Асан Б.", amount: 30_000,
            currency: "KZT", type: .expense, category: "", accountId: nil
        )
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: row, accountId: "freedom", category: "Food", subcategoryIds: [loved.id],
                              transferAccountId: nil, mergeWith: nil)
        ])
        await ImportCommitter.commit(operations, store: graph.store, categories: graph.categories, balance: graph.balance)

        #expect(graph.store.transactionById["r1"]?.category == "Food")
        #expect(graph.store.subcategoryIdsByTransactionId["r1"] == [loved.id])
        #expect(graph.store.subcategoryIdsByCategoryId[food.id]?.contains(loved.id) == true)
    }
}
