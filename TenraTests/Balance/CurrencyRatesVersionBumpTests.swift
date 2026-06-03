//
//  CurrencyRatesVersionBumpTests.swift
//  TenraTests
//
//  Pins the contract added in cache audit #1: bumpCurrencyRatesVersion() must
//  report whether it healed cold-cache (FX-stale) aggregates, because the caller
//  (AppCoordinator's rate observer) uses that signal to also recalculate balances.
//  Without the return value the balance cache stayed at the cold rate until restart.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CurrencyRatesVersionBumpTests {

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

    @Test("bump returns false and does not clear when aggregates are not FX-stale")
    func bumpWhenFresh() {
        let store = Self.makeStore()
        store.aggregatesAreFXStale = false
        let before = store.currencyRatesVersion

        let didHeal = store.bumpCurrencyRatesVersion()

        #expect(didHeal == false)
        #expect(store.currencyRatesVersion != before) // version always bumps
    }

    @Test("bump returns true and clears the stale flag when aggregates are FX-stale")
    func bumpWhenStale() {
        let store = Self.makeStore()
        store.aggregatesAreFXStale = true

        let didHeal = store.bumpCurrencyRatesVersion()

        #expect(didHeal == true)
        #expect(store.aggregatesAreFXStale == false) // rebuild cleared it
    }
}
