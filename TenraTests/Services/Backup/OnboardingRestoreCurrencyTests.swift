//
//  OnboardingRestoreCurrencyTests.swift
//  TenraTests
//
//  A backup holds the data, not the settings (they live in UserDefaults): after a restore from
//  onboarding the base currency follows the restored accounts. Pins the rule that picks it.
//

import Testing
@testable import Tenra

@MainActor
struct OnboardingRestoreCurrencyTests {

    private func account(_ currency: String) -> Account {
        Account(name: currency, currency: currency, iconSource: nil, shouldCalculateFromTransactions: false, initialBalance: 0, includeInBalance: true)
    }

    @Test("The currency most accounts use wins")
    func mostAccounts() {
        let accounts = [account("USD"), account("KZT"), account("KZT")]
        #expect(CloudSyncViewModel.dominantCurrency(of: accounts) == "KZT")
    }

    @Test("A tie goes to the first account's currency")
    func tieGoesToFirst() {
        let accounts = [account("EUR"), account("KZT")]
        #expect(CloudSyncViewModel.dominantCurrency(of: accounts) == "EUR")
    }

    @Test("No accounts, no currency")
    func none() {
        #expect(CloudSyncViewModel.dominantCurrency(of: []) == nil)
    }
}
