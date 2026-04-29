//
//  JsDelivrCurrencyProviderTests.swift
//  TenraTests
//
//  Verifies the JSON parser of the jsDelivr provider against the documented
//  API response shape. No network calls — uses fixture JSON.
//

import Testing
import Foundation
@testable import Tenra

struct JsDelivrCurrencyProviderTests {

    // MARK: - Fixture

    /// Realistic jsDelivr response shape, abbreviated.
    private static let sampleJSON = """
    {
        "date": "2024-04-29",
        "usd": {
            "kzt": 442.5,
            "eur": 0.93,
            "rub": 91.2,
            "usd": 1.0
        }
    }
    """.data(using: .utf8)!

    // MARK: - Parse smoke test

    @Test("Parses valid jsDelivr response into KZT-pivot rates")
    func parsesValidResponse() throws {
        let result = try JsDelivrCurrencyProvider.parse(
            data: Self.sampleJSON,
            apiBase: "USD",
            requestedDate: Date()
        )

        // After parsing, `rates` is in convention A relative to USD pivot:
        //   rates[X] = USD per 1 X = 1 / api[X]
        // Re-pivot to KZT — that's what CurrencyRateStore does internally.
        let kztPivot = try #require(result.normalized(toPivot: "KZT"))

        // 1 USD = 442.5 KZT (api), so kztPivot["USD"] should be 442.5.
        let usd = try #require(kztPivot["USD"])
        #expect(abs(usd - 442.5) < 0.001)

        // 1 EUR = (USD per 1 EUR) / (USD per 1 KZT) * KZT
        //       = (1/0.93) / (1/442.5) = 442.5 / 0.93 ≈ 475.806
        let eur = try #require(kztPivot["EUR"])
        #expect(abs(eur - (442.5 / 0.93)) < 0.001)

        // RUB
        let rub = try #require(kztPivot["RUB"])
        #expect(abs(rub - (442.5 / 91.2)) < 0.001)

        // KZT itself is the new pivot — must not be a key.
        #expect(kztPivot["KZT"] == nil)
    }

    @Test("Provider name is jsdelivr")
    func providerNameMatches() throws {
        let result = try JsDelivrCurrencyProvider.parse(
            data: Self.sampleJSON,
            apiBase: "USD",
            requestedDate: Date()
        )
        #expect(result.providerName == "jsdelivr")
    }

    @Test("Date field parsed from response")
    func parsesResponseDate() throws {
        let result = try JsDelivrCurrencyProvider.parse(
            data: Self.sampleJSON,
            apiBase: "USD",
            requestedDate: Date()
        )

        var components = DateComponents()
        components.year = 2024
        components.month = 4
        components.day = 29
        components.timeZone = TimeZone(identifier: "UTC")
        let expected = Calendar(identifier: .gregorian).date(from: components)
        #expect(result.date == expected)
    }

    // MARK: - Error paths

    @Test("Throws when JSON is malformed")
    func throwsOnMalformedJSON() {
        let bogus = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JsDelivrCurrencyProvider.parse(
                data: bogus,
                apiBase: "USD",
                requestedDate: Date()
            )
        }
    }

    @Test("Throws when base key missing")
    func throwsWhenBaseKeyMissing() {
        let json = """
        {"date": "2024-04-29", "eur": {"kzt": 475.8}}
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JsDelivrCurrencyProvider.parse(
                data: json,
                apiBase: "USD",
                requestedDate: Date()
            )
        }
    }

    @Test("Throws when response contains no usable rates")
    func throwsOnEmptyRates() {
        let json = """
        {"date": "2024-04-29", "usd": {}}
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JsDelivrCurrencyProvider.parse(
                data: json,
                apiBase: "USD",
                requestedDate: Date()
            )
        }
    }

    @Test("Skips entries with non-positive rates")
    func skipsZeroAndNegativeRates() throws {
        let json = """
        {
            "date": "2024-04-29",
            "usd": {"kzt": 442.5, "xyz": 0, "abc": -1}
        }
        """.data(using: .utf8)!
        let result = try JsDelivrCurrencyProvider.parse(
            data: json,
            apiBase: "USD",
            requestedDate: Date()
        )
        #expect(result.rates["KZT"] != nil)
        #expect(result.rates["XYZ"] == nil)
        #expect(result.rates["ABC"] == nil)
    }
}
