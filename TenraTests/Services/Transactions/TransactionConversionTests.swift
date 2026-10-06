//
//  TransactionConversionTests.swift
//  TenraTests
//
//  Pins the one rule for a transaction's stored conversion fields
//  (TransactionConversion): `convertedAmount` in the ACCOUNT's currency (never the
//  base value the add screen used to store), the equivalent in targetCurrency /
//  targetAmount, a transfer's two legs, and the saved rate an edit keeps.
//
//  @MainActor + .sharedProcessState: `keepingRates` reads the process-global
//  CurrencyRateStore.shared, cleared in init (CLAUDE.md "Testing").
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct TransactionConversionTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Fixtures

    /// KZT per unit: 1 USD = 500 KZT, 1 EUR = 550 KZT.
    private nonisolated static func fixedRates(_ amount: Double, _ from: String, _ to: String) -> Double? {
        let kztPerUnit: [String: Double] = ["KZT": 1, "USD": 500, "EUR": 550]
        guard let fromRate = kztPerUnit[from], let toRate = kztPerUnit[to] else { return nil }
        return amount * fromRate / toRate
    }

    private nonisolated static func noRates(_ amount: Double, _ from: String, _ to: String) -> Double? { nil }

    /// Same rates in the process-wide cache, for code that reads `convertSync`.
    private func seedCache() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500, "EUR": 550],
            date: Date(),
            providerName: "test"
        ))
    }

    private func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.0001
    }

    private func expense(
        amount: Double, currency: String, accountId: String = "a1",
        convertedAmount: Double? = nil, targetCurrency: String? = nil, targetAmount: Double? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: "2026-09-01", description: "x",
            amount: amount, currency: currency, convertedAmount: convertedAmount,
            type: .expense, category: "Food", accountId: accountId,
            targetCurrency: targetCurrency, targetAmount: targetAmount
        )
    }

    // MARK: - Single-account rule

    @Test("foreign currency: convertedAmount and the equivalent are in the account's currency")
    func singleAccountForeignCurrency() throws {
        let fields = try #require(TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "KZT", baseCurrency: "KZT",
            convert: Self.fixedRates
        ))
        #expect(fields.convertedAmount == 5_000)
        #expect(fields.targetCurrency == "KZT")
        #expect(fields.targetAmount == 5_000)
    }

    @Test("account in another currency than base: convertedAmount is NOT the base value")
    func singleAccountNonBaseAccount() throws {
        // The add screen stored the base value (5 000 KZT) as convertedAmount, which the
        // balance and the CSV round trip read in the account's currency (euros).
        let fields = try #require(TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "EUR", baseCurrency: "KZT",
            convert: Self.fixedRates
        ))
        #expect(close(fields.convertedAmount, 5_000.0 / 550.0))
        #expect(fields.targetCurrency == "EUR")
        #expect(close(fields.targetAmount, 5_000.0 / 550.0))
    }

    @Test("already in the account's foreign currency: only a base-currency display equivalent")
    func singleAccountSameCurrency() throws {
        let fields = try #require(TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "USD", baseCurrency: "KZT",
            convert: Self.fixedRates
        ))
        #expect(fields.convertedAmount == nil)
        #expect(fields.targetCurrency == "KZT")
        #expect(fields.targetAmount == 5_000)
    }

    @Test("a missing account-currency rate is nil; a missing display rate is not")
    func singleAccountMissingRate() {
        #expect(TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "KZT", baseCurrency: "KZT",
            convert: Self.noRates
        ) == nil)
        #expect(TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "USD", baseCurrency: "KZT",
            convert: Self.noRates
        ) == TransactionConversion())
    }

    // MARK: - Transfer rule

    @Test("transfer: source leg in the source currency, target leg in the target currency")
    func transferBothLegs() throws {
        let fields = try #require(TransactionConversion.transfer(
            amount: 10, currency: "USD", sourceCurrency: "KZT", targetCurrency: "EUR",
            convert: Self.fixedRates
        ))
        #expect(fields.convertedAmount == 5_000)
        #expect(fields.targetCurrency == "EUR")
        #expect(close(fields.targetAmount, 5_000.0 / 550.0))

        let sameCurrency = try #require(TransactionConversion.transfer(
            amount: 700, currency: "KZT", sourceCurrency: "KZT", targetCurrency: "KZT",
            convert: Self.noRates
        ))
        #expect(sameCurrency == TransactionConversion(targetCurrency: "KZT", targetAmount: 700))
        #expect(TransactionConversion.transfer(
            amount: 10, currency: "USD", sourceCurrency: "USD", targetCurrency: "KZT",
            convert: Self.noRates
        ) == nil)
    }

    // MARK: - Stored rate

    @Test("storedRate reads the rate the transaction was saved with")
    func storedRateReadsSavedRate() {
        // Saved by the add screen: equivalent in targetAmount, at 480 ₸/$.
        let added = expense(amount: 10, currency: "USD", convertedAmount: 4_800,
                            targetCurrency: "KZT", targetAmount: 4_800)
        #expect(TransactionConversion.storedRate(in: added, from: "USD", to: "KZT", accountCurrency: "KZT") == 480)

        // Saved by voice / a top-up / an old edit: only convertedAmount, in account currency.
        let converted = expense(amount: 10, currency: "USD", convertedAmount: 4_800)
        #expect(TransactionConversion.storedRate(in: converted, from: "USD", to: "KZT", accountCurrency: "KZT") == 480)
        // ...which says nothing about another pair.
        #expect(TransactionConversion.storedRate(in: converted, from: "USD", to: "EUR", accountCurrency: "KZT") == nil)
        #expect(TransactionConversion.storedRate(in: converted, from: "EUR", to: "KZT", accountCurrency: "KZT") == nil)
    }

    @Test("keepingRates reuses the saved rate and falls back to the cache for other pairs")
    func keepingRatesPrefersSavedRate() {
        seedCache()
        let saved = expense(amount: 10, currency: "USD", targetCurrency: "KZT", targetAmount: 4_800)
        let convert = TransactionConversion.keepingRates(of: saved, accountCurrency: "KZT")

        #expect(convert(20, "USD", "KZT") == 9_600)        // 480 ₸/$, not today's 500
        #expect(close(convert(10, "EUR", "KZT"), 5_500))   // no saved EUR rate: cache
    }

    @Test("a missing base-currency equivalent asks the caller to load rates once more")
    func lacksEquivalentOnColdCache() {
        // Dollars on a dollar account, tenge base, no rate: saved without the "≈" line.
        let cold = TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "USD", baseCurrency: "KZT",
            convert: Self.noRates
        )
        #expect(cold == TransactionConversion())
        if let cold {
            #expect(TransactionConversion.lacksEquivalent(cold, currency: "USD", baseCurrency: "KZT"))
        }

        let warm = TransactionConversion.singleAccount(
            amount: 10, currency: "USD", accountCurrency: "USD", baseCurrency: "KZT",
            convert: Self.fixedRates
        )
        if let warm {
            #expect(!TransactionConversion.lacksEquivalent(warm, currency: "USD", baseCurrency: "KZT"))
        }
        // In the base currency there is no equivalent to show.
        #expect(!TransactionConversion.lacksEquivalent(TransactionConversion(), currency: "KZT", baseCurrency: "KZT"))
    }
}
