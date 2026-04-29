//
//  CurrencyRateStorePersistenceTests.swift
//  TenraTests
//
//  Verifies that `CurrencyRateStore` round-trips its current-rates snapshot
//  through UserDefaults so `convertSync` works at T=0 on warm-launch.
//
//  Note: these tests touch the singleton `CurrencyRateStore.shared` and the
//  app's UserDefaults. We snapshot/restore the relevant key around each test
//  to avoid leaking state into the running simulator.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CurrencyRateStorePersistenceTests {

    private static let userDefaultsKey = "currency.rates.cache.v1"

    // MARK: - Helpers

    private func snapshotDefaults() -> Data? {
        UserDefaults.standard.data(forKey: Self.userDefaultsKey)
    }

    private func restoreDefaults(_ data: Data?) {
        if let data {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        }
    }

    // MARK: - Tests

    @Test("updateCurrentRates persists rates to UserDefaults")
    func persistRoundTrip() throws {
        let backup = snapshotDefaults()
        defer { restoreDefaults(backup) }

        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)

        let store = CurrencyRateStore.shared
        store.clearAll()

        let snapshot = ExchangeRates(
            pivot: "USD",
            rates: ["KZT": 1.0 / 442.5, "EUR": 1.0 / 0.93],
            date: Date(),
            providerName: "test-provider"
        )
        store.updateCurrentRates(snapshot)

        // Re-read the UserDefaults blob and decode it manually — verifies wire format.
        let raw = try #require(UserDefaults.standard.data(forKey: Self.userDefaultsKey))
        let decoded = try JSONDecoder().decode(PersistedRatesDTO.self, from: raw)

        #expect(decoded.pivot == "KZT")
        #expect(decoded.providerName == "test-provider")
        let usd = try #require(decoded.rates["USD"])
        #expect(abs(usd - 442.5) < 0.001)
    }

    @Test("convertSync works immediately after updateCurrentRates")
    func convertSyncWorksAfterUpdate() {
        let backup = snapshotDefaults()
        defer { restoreDefaults(backup) }

        let store = CurrencyRateStore.shared
        store.clearAll()

        let snapshot = ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 442.5, "EUR": 475.8],
            date: Date(),
            providerName: "test"
        )
        store.updateCurrentRates(snapshot)

        // 100 USD → KZT
        let kzt = CurrencyConverter.convertSync(amount: 100, from: "USD", to: "KZT")
        #expect(kzt == 100.0 * 442.5)

        // 100 KZT → USD
        let usd = CurrencyConverter.convertSync(amount: 100, from: "KZT", to: "USD")
        #expect(usd != nil)
        if let usd { #expect(abs(usd - 100.0 / 442.5) < 0.0001) }

        // 100 USD → EUR via KZT pivot
        let eur = CurrencyConverter.convertSync(amount: 100, from: "USD", to: "EUR")
        #expect(eur != nil)
        if let eur { #expect(abs(eur - (100.0 * 442.5 / 475.8)) < 0.0001) }
    }

    @Test("convertSync returns nil when rates absent")
    func convertSyncReturnsNilWithoutRates() {
        let backup = snapshotDefaults()
        defer { restoreDefaults(backup) }

        CurrencyRateStore.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)

        let result = CurrencyConverter.convertSync(amount: 100, from: "USD", to: "EUR")
        #expect(result == nil)
    }

    @Test("convertSync returns same amount when from==to")
    func convertSyncIdentity() {
        let result = CurrencyConverter.convertSync(amount: 42, from: "USD", to: "USD")
        #expect(result == 42)
    }

    @Test("clearAll removes both memory and disk state")
    func clearAllWipesEverything() {
        let backup = snapshotDefaults()
        defer { restoreDefaults(backup) }

        let store = CurrencyRateStore.shared
        store.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 442.5],
            date: Date(),
            providerName: "test"
        ))
        #expect(store.cachedRates["USD"] != nil)

        store.clearAll()
        #expect(store.cachedRates.isEmpty)
        #expect(UserDefaults.standard.data(forKey: Self.userDefaultsKey) == nil)
    }

    // MARK: - DTO mirror

    /// Mirror of `PersistedRates` (which is fileprivate) so the test can decode
    /// the on-disk payload independently.
    private struct PersistedRatesDTO: Decodable {
        let pivot: String
        let rates: [String: Double]
        let fetchedAt: Date
        let providerName: String
    }
}
