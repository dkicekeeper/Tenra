//
//  CategoryRenameTests.swift
//  TenraTests
//
//  Categories are referenced by NAME (Transaction.category, TransactionEntity.category,
//  RecurringSeries.category). Renaming a category used to re-key only the in-memory
//  indexes: old transactions kept the old name, so editing one failed validation with
//  categoryNotFound, the category emptied after relaunch, and series kept generating
//  the old name. These tests pin that a rename rewrites the stored names.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryRenameTests {

    private struct Graph {
        let store: TransactionStore
        let repo: RecordingDataRepository
        let food: CustomCategory
    }

    private static func makeGraph() -> Graph {
        let repo = RecordingDataRepository()
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: recurring)
        let food = CustomCategory(name: "Food", iconSource: .sfSymbol("cart"), colorHex: "#22c55e", type: .expense)
        store.addCategory(food)
        store.addCategory(CustomCategory(name: "Salary", iconSource: .sfSymbol("briefcase"), colorHex: "#16a34a", type: .income))
        store.accounts = [
            Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "a2", name: "Other", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        return Graph(store: store, repo: repo, food: food)
    }

    private static func tx(
        _ id: String,
        type: TransactionType = .expense,
        category: String = "Food",
        subcategory: String? = nil,
        target: String? = nil
    ) -> Transaction {
        Transaction(
            id: id, date: "2026-09-01", description: "MAGNUM", amount: 1500, currency: "KZT",
            type: type, category: category, subcategory: subcategory,
            accountId: "a1", targetAccountId: target
        )
    }

    private static func rename(_ graph: Graph, to newName: String) {
        var renamed = graph.food
        renamed.name = newName
        graph.store.updateCategory(renamed)
    }

    @Test func renameRewritesExpenseTransactions() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1"))
        _ = try await g.store.add(Self.tx("t2"))

        Self.rename(g, to: "Groceries")

        #expect(g.store.transactionById["t1"]?.category == "Groceries")
        #expect(g.store.transactionById["t2"]?.category == "Groceries")
        #expect(g.store.transactions.filter { $0.category == "Food" }.isEmpty)
    }

    @Test func oldTransactionIsEditableAfterRename() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1"))
        Self.rename(g, to: "Groceries")

        let current = try #require(g.store.transactionById["t1"])
        let edited = Transaction(
            id: current.id, date: current.date, description: current.description, amount: 2500,
            currency: current.currency, type: current.type, category: current.category,
            accountId: current.accountId, createdAt: current.createdAt
        )
        try await g.store.update(edited)
        #expect(g.store.transactionById["t1"]?.amount == 2500)
    }

    @Test func coldIndexRebuildKeepsTransactionsUnderNewName() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1"))
        Self.rename(g, to: "Groceries")

        g.store.rebuildCategoryIndexes()

        #expect(g.store.transactionIdsByCategoryName["Groceries"]?.contains("t1") == true)
        #expect(g.store.transactionIdsByCategoryName["Food"] == nil)
    }

    @Test func incomeWithSameNameIsNotRenamed() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("inc", type: .income, category: "Food"))
        Self.rename(g, to: "Groceries")
        #expect(g.store.transactionById["inc"]?.category == "Food")
    }

    @Test func loanPaymentTaggedWithExpenseCategoryIsRenamed() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("loan", type: .loanPayment, category: "Food", target: "a2"))
        Self.rename(g, to: "Groceries")
        #expect(g.store.transactionById["loan"]?.category == "Groceries")
    }

    @Test func recurringSeriesIsRenamed() async throws {
        let g = Self.makeGraph()
        let series = RecurringSeries(
            id: "s1", isActive: true, amount: Decimal(4990), currency: "KZT",
            category: "Food", description: "Delivery", frequency: .monthly, startDate: "2026-09-01"
        )
        g.store.recurringStore.handleSeriesCreated(series)

        Self.rename(g, to: "Groceries")

        #expect(g.store.recurringStore.seriesById["s1"]?.category == "Groceries")
    }

    @Test func legacySubcategoryStringIsKept() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1", subcategory: "Snacks"))
        Self.rename(g, to: "Groceries")
        #expect(g.store.transactionById["t1"]?.subcategory == "Snacks")
    }

    @Test func mutationVersionBumpsOnlyWhenTransactionsChanged() async throws {
        let g = Self.makeGraph()
        let before = g.store.mutationVersion
        Self.rename(g, to: "Groceries")                 // no transactions yet
        #expect(g.store.mutationVersion == before)

        _ = try await g.store.add(Self.tx("t1", category: "Groceries"))
        let afterAdd = g.store.mutationVersion
        var groceries = try #require(g.store.categories.first { $0.name == "Groceries" })
        groceries.name = "Food & Groceries"
        g.store.updateCategory(groceries)
        #expect(g.store.mutationVersion > afterAdd)
    }

    @Test func renameIsPersisted() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1"))
        _ = try await g.store.add(Self.tx("t2"))
        Self.rename(g, to: "Groceries")

        let calls = g.repo.categoryRenames
        #expect(calls.count == 1)
        #expect(calls.first?.newName == "Groceries")
        #expect(Set(calls.first?.ids ?? []) == ["t1", "t2"])
    }
}
