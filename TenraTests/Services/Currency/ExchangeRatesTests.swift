//
//  ExchangeRatesTests.swift
//  TenraTests
//
//  Verifies the pivot-conversion math in `ExchangeRates.normalized(toPivot:)`.
//

import Testing
import Foundation
@testable import Tenra

struct ExchangeRatesTests {

    // MARK: - Same-pivot is identity

    @Test("Same pivot returns the original rates dict")
    func sameDistinctPivotReturnsIdentity() {
        let rates = ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 442.5, "EUR": 475.8],
            date: Date(),
            providerName: "test"
        )
        let result = rates.normalized(toPivot: "KZT")
        #expect(result == ["USD": 442.5, "EUR": 475.8])
    }

    // MARK: - USD-pivot → KZT-pivot (the jsDelivr → internal storage path)

    @Test("Re-pivot USD → KZT preserves cross-rates")
    func repivotUSDToKZT() throws {
        // Source: pivot=USD, rates[X] = USD per 1 X.
        // 1 KZT = 1/442.5 USD ≈ 0.00226
        // 1 EUR = 1/0.93 USD ≈ 1.0753
        let rates = ExchangeRates(
            pivot: "USD",
            rates: ["KZT": 1.0 / 442.5, "EUR": 1.0 / 0.93],
            date: Date(),
            providerName: "test"
        )
        let result = try #require(rates.normalized(toPivot: "KZT"))

        // After re-pivot to KZT: rates[X] = KZT per 1 X.
        //   USD: should be ≈ 442.5 (the original "1 USD = 442.5 KZT")
        //   EUR: should be ≈ 442.5 / 0.93 ≈ 475.806
        let usd = try #require(result["USD"])
        let eur = try #require(result["EUR"])
        #expect(abs(usd - 442.5) < 0.001)
        #expect(abs(eur - (442.5 / 0.93)) < 0.001)
        // KZT is the pivot now and must NOT be in rates dict.
        #expect(result["KZT"] == nil)
    }

    // MARK: - Failure cases

    @Test("Re-pivot returns nil when target currency missing")
    func repivotMissingTarget() {
        let rates = ExchangeRates(
            pivot: "USD",
            rates: ["EUR": 0.93],   // KZT not present
            date: Date(),
            providerName: "test"
        )
        #expect(rates.normalized(toPivot: "KZT") == nil)
    }

    @Test("Re-pivot returns nil when target rate is zero")
    func repivotZeroTargetRate() {
        let rates = ExchangeRates(
            pivot: "USD",
            rates: ["KZT": 0.0],
            date: Date(),
            providerName: "test"
        )
        #expect(rates.normalized(toPivot: "KZT") == nil)
    }

    // MARK: - Round-trip property

    @Test("USD→KZT→USD round-trip preserves rates within tolerance")
    func roundTripUSDtoKZT() throws {
        let original = ExchangeRates(
            pivot: "USD",
            rates: [
                "KZT": 1.0 / 442.5,
                "EUR": 1.0 / 0.93,
                "RUB": 1.0 / 91.2
            ],
            date: Date(),
            providerName: "test"
        )
        let kztPivot = try #require(original.normalized(toPivot: "KZT"))
        // Build an ExchangeRates wrapping the KZT-pivot result and re-pivot back to USD.
        let kztPivotRates = ExchangeRates(
            pivot: "KZT",
            rates: kztPivot,
            date: original.date,
            providerName: "test"
        )
        let usdPivot = try #require(kztPivotRates.normalized(toPivot: "USD"))

        for (code, originalValue) in original.rates {
            let roundtrip = try #require(usdPivot[code])
            let relError = abs(roundtrip - originalValue) / originalValue
            #expect(relError < 0.0001, "round-trip diverged for \(code)")
        }
    }
}
