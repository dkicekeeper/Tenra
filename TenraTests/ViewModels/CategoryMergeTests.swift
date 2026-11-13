//
//  CategoryMergeTests.swift
//  TenraTests
//
//  Folding one category into another (TransactionStore.mergeCategory, the assistant's
//  `draft_category_change`): the folded category's records take the other's name and it is
//  deleted; undo puts the category back with the records it had, and leaves alone a record
//  edited since. Categories are referenced by NAME, as in CategoryRenameTests.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryMergeTests {

    private struct Graph {
        let store: TransactionStore
        let cafe: CustomCategory
        let food: CustomCategory
        let salary: CustomCategory
    }

    private static func makeGraph() -> Graph {
        let repo = RecordingDataRepository()
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        let cafe = CustomCategory(name: "Cafe", iconSource: .sfSymbol("cup.and.saucer"), colorHex: "#f97316", type: .expense)
        let food = CustomCategory(name: "Food", iconSource: .sfSymbol("cart"), colorHex: "#22c55e", type: .expense)
        let salary = CustomCategory(name: "Salary", iconSource: .sfSymbol("briefcase"), colorHex: "#16a34a", type: .income)
        for category in [cafe, food, salary] { store.addCategory(category) }
        store.accounts = [Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0)]
        store.rebuildAccountById()
        return Graph(store: store, cafe: cafe, food: food, salary: salary)
    }

    private static func tx(_ id: String, category: String) -> Transaction {
        Transaction(
            id: id, date: "2026-09-01", description: "MAGNUM", amount: 1500, currency: "KZT",
            type: .expense, category: category, accountId: "a1"
        )
    }

    @Test func aMergeMovesTheRecordsAndDeletesTheCategory() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1", category: "Cafe"))
        _ = try await g.store.add(Self.tx("t2", category: "Cafe"))
        _ = try await g.store.add(Self.tx("t3", category: "Food"))

        let merge = try #require(g.store.mergeCategory(g.cafe.id, into: g.food.id))

        #expect(Set(merge.transactionIds) == ["t1", "t2"])
        #expect(g.store.categoryById[g.cafe.id] == nil)
        #expect(g.store.transactions.allSatisfy { $0.category == "Food" })
        #expect(g.store.transactionById["t1"]?.category == "Food")
    }

    @Test func undoPutsTheCategoryBackWithItsRecords() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1", category: "Cafe"))
        _ = try await g.store.add(Self.tx("t2", category: "Cafe"))
        _ = try await g.store.add(Self.tx("t3", category: "Food"))
        let merge = try #require(g.store.mergeCategory(g.cafe.id, into: g.food.id))

        g.store.undoCategoryMerge(merge)

        #expect(g.store.categoryById[g.cafe.id]?.name == "Cafe")
        #expect(g.store.transactionById["t1"]?.category == "Cafe")
        #expect(g.store.transactionById["t2"]?.category == "Cafe")
        #expect(g.store.transactionById["t3"]?.category == "Food")
    }

    @Test func anExpenseCategoryIsNotMergedIntoAnIncomeOne() async throws {
        let g = Self.makeGraph()
        _ = try await g.store.add(Self.tx("t1", category: "Cafe"))

        #expect(g.store.mergeCategory(g.cafe.id, into: g.salary.id) == nil)
        #expect(g.store.mergeCategory(g.cafe.id, into: g.cafe.id) == nil)
        #expect(g.store.categoryById[g.cafe.id] != nil)
        #expect(g.store.transactionById["t1"]?.category == "Cafe")
    }
}
