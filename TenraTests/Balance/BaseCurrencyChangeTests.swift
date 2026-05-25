//
//  BaseCurrencyChangeTests.swift
//  TenraTests
//
//  Guards the now load-bearing `TransactionStore.updateBaseCurrency` primitive.
//  C-1: base-currency change used to be inert because this method had no callers;
//  it is now invoked from SettingsViewModel. These pin its observable contract so
//  a future refactor can't silently make it a no-op again.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct BaseCurrencyChangeTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        return TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
    }

    @Test("updateBaseCurrency changes the store currency and invalidates category aggregates")
    func updatesCurrencyAndBumpsVersion() async {
        let store = Self.makeStore()
        store.accounts = [Account(id: "a1", name: "Bank", currency: "KZT", createdDate: Date(), balance: 0)]
        store.rebuildAccountById()

        #expect(store.baseCurrency == "KZT")
        let before = store.categoriesMutationVersion

        store.updateBaseCurrency("USD")

        #expect(store.baseCurrency == "USD")
        #expect(store.categoriesMutationVersion != before)
    }

    @Test("updateBaseCurrency to the same currency is a no-op for the version")
    func sameCurrencyNoVersionBump() async {
        let store = Self.makeStore()
        store.accounts = [Account(id: "a1", name: "Bank", currency: "KZT", createdDate: Date(), balance: 0)]
        store.rebuildAccountById()
        store.baseCurrency = "USD"
        let before = store.categoriesMutationVersion

        store.updateBaseCurrency("USD")

        #expect(store.categoriesMutationVersion == before)
    }
}
