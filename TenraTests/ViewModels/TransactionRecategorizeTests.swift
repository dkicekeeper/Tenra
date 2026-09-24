//
//  TransactionRecategorizeTests.swift
//  TenraTests
//
//  Pins TransactionStore.recategorize, the write side of the "apply to similar"
//  prompt: only rows still carrying the expected category move, unknown ids are
//  skipped, and nothing but the category changes.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionRecategorizeTests {

    // MARK: - Harness (mirrors TransactionSeriesDetachTests)

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: balance,
            recurringStore: recurring
        )
        store.categories = [
            CustomCategory(name: "Groceries", iconSource: .sfSymbol("cart"),
                           colorHex: "#22c55e", type: .expense),
            CustomCategory(name: "Snacks", iconSource: .sfSymbol("takeoutbag.and.cup.and.straw"),
                           colorHex: "#f97316", type: .expense)
        ]
        store.accounts = [
            Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        return store
    }

    private static func tx(_ id: String, category: String = "", amount: Double = 1500) -> Transaction {
        Transaction(
            id: id,
            date: "2026-09-01",
            description: "MAGNUM CASH&CARRY",
            amount: amount,
            currency: "KZT",
            type: .expense,
            category: category,
            accountId: "a1",
            createdAt: 1_700_000_000
        )
    }

    @Test func movesAllMatchingRows() async throws {
        let store = Self.makeStore()
        for id in ["m1", "m2", "m3"] { _ = try await store.add(Self.tx(id)) }

        let updated = await store.recategorize(ids: ["m1", "m2", "m3"], from: "", to: "Groceries")

        #expect(updated == 3)
        for id in ["m1", "m2", "m3"] {
            #expect(store.transactionById[id]?.category == "Groceries")
        }
    }

    @Test func rowEditedMeanwhileIsSkipped() async throws {
        let store = Self.makeStore()
        _ = try await store.add(Self.tx("m1"))
        _ = try await store.add(Self.tx("m2", category: "Snacks"))

        let updated = await store.recategorize(ids: ["m1", "m2"], from: "", to: "Groceries")

        #expect(updated == 1)
        #expect(store.transactionById["m1"]?.category == "Groceries")
        #expect(store.transactionById["m2"]?.category == "Snacks")
    }

    @Test func unknownIdIsSkipped() async throws {
        let store = Self.makeStore()
        _ = try await store.add(Self.tx("m1"))

        let updated = await store.recategorize(ids: ["missing", "m1"], from: "", to: "Groceries")

        #expect(updated == 1)
    }

    @Test func onlyTheCategoryChanges() async throws {
        let store = Self.makeStore()
        _ = try await store.add(Self.tx("m1", amount: 4200))
        let before = try #require(store.transactionById["m1"])

        _ = await store.recategorize(ids: ["m1"], from: "", to: "Groceries")

        let after = try #require(store.transactionById["m1"])
        #expect(after.category == "Groceries")
        #expect(after.amount == before.amount)
        #expect(after.currency == before.currency)
        #expect(after.accountId == before.accountId)
        #expect(after.date == before.date)
        #expect(after.description == before.description)
        #expect(after.createdAt == before.createdAt)
        #expect(after.type == before.type)
    }
}
