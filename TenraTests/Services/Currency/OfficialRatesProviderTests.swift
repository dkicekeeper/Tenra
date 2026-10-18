//
//  OfficialRatesProviderTests.swift
//  TenraTests
//
//  The fallback after the CDN: the ECB's euro table, parsed from its XML, put into tenge through
//  the National Bank's euro rate (or the cached one while the bank is down), with the bank's own
//  currencies added; the bank alone while the ECB is down. No network calls: fixture XML and
//  stub providers.
//

import Testing
import Foundation
@testable import Tenra

struct OfficialRatesProviderTests {

    // MARK: - Fixtures

    /// The 90-day file's shape, newest day first, abbreviated.
    private static let historyXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
        <gesmes:subject>Reference rates</gesmes:subject>
        <gesmes:Sender>
            <gesmes:name>European Central Bank</gesmes:name>
        </gesmes:Sender>
        <Cube>
            <Cube time='2026-10-16'>
                <Cube currency='USD' rate='1.0800'/>
                <Cube currency='KRW' rate='1500.00'/>
                <Cube currency='JPY' rate='160.00'/>
            </Cube>
            <Cube time='2026-10-15'>
                <Cube currency='USD' rate='1.0700'/>
                <Cube currency='KRW' rate='1480.00'/>
            </Cube>
        </Cube>
    </gesmes:Envelope>
    """.data(using: .utf8)!

    private static func day(_ key: String) -> Date {
        DateFormatters.rateDateFormatter.date(from: key)!
    }

    private struct StubProvider: CurrencyRateProvider {
        let name: String
        let result: Result<ExchangeRates, Error>

        func fetchRates(on date: Date?) async throws -> ExchangeRates {
            try result.get()
        }
    }

    private static let euro = ExchangeRates(pivot: "EUR", rates: ["USD": 1 / 1.08, "KRW": 1 / 1500.0], date: day("2026-10-16"), providerName: "ecb")
    private static let tenge = ExchangeRates(pivot: "KZT", rates: ["EUR": 540, "USD": 501, "RUB": 6], date: day("2026-10-16"), providerName: "nbk")

    private static func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9 * max(1, abs(expected))
    }

    // MARK: - ECB parser

    @Test("the latest day's table, inverted into euros per unit")
    func parsesTheLatestDay() throws {
        let rates = try ECBCurrencyProvider.parse(data: Self.historyXML, on: nil)
        #expect(rates.pivot == "EUR")
        #expect(rates.providerName == "ecb")
        #expect(CurrencyConverter.dateKey(for: rates.date) == "2026-10-16")
        #expect(Self.close(rates.rates["USD"], 1 / 1.08))
        #expect(Self.close(rates.rates["KRW"], 1 / 1500.0))
        #expect(Self.close(rates.rates["JPY"], 1 / 160.0))
    }

    @Test("a weekend takes the last working day; a day before the file has none")
    func historicalDatesTakeTheLastWorkingDay() throws {
        let sunday = try ECBCurrencyProvider.parse(data: Self.historyXML, on: Self.day("2026-10-18"))
        #expect(CurrencyConverter.dateKey(for: sunday.date) == "2026-10-16")

        let thursday = try ECBCurrencyProvider.parse(data: Self.historyXML, on: Self.day("2026-10-15"))
        #expect(Self.close(thursday.rates["KRW"], 1 / 1480.0))
        #expect(thursday.rates["JPY"] == nil)

        #expect(throws: CurrencyProviderError.self) {
            _ = try ECBCurrencyProvider.parse(data: Self.historyXML, on: Self.day("2026-10-10"))
        }
    }

    // MARK: - The table in tenge

    @Test("the ECB's table in tenge through the bank's euro rate, with the bank's own currencies")
    func combinesWithTheBank() throws {
        let rates = try OfficialRatesProvider.combine(euro: Self.euro, tenge: Self.tenge, cachedTengePerEuro: nil)
        #expect(rates.pivot == "KZT")
        #expect(rates.providerName == "ecb+nbk")
        #expect(Self.close(rates.rates["EUR"], 540))
        // The ECB's dollar, not the bank's: pairs without the tenge are the ECB's exactly.
        #expect(Self.close(rates.rates["USD"], 540 / 1.08))
        #expect(Self.close(rates.rates["KRW"], 540 / 1500.0))
        #expect(Self.close(rates.rates["RUB"], 6))
        // Won per dollar as the ECB quotes it.
        let usd = try #require(rates.rates["USD"])
        let krw = try #require(rates.rates["KRW"])
        #expect(Self.close(usd / krw, 1500 / 1.08))
    }

    @Test("with the bank down, the cached euro rate anchors the table")
    func anchorsOnTheCacheWithoutTheBank() throws {
        let rates = try OfficialRatesProvider.combine(euro: Self.euro, tenge: nil, cachedTengePerEuro: 550)
        #expect(rates.providerName == "ecb")
        #expect(Self.close(rates.rates["USD"], 550 / 1.08))
        #expect(rates.rates["RUB"] == nil)

        #expect(throws: CurrencyProviderError.self) {
            _ = try OfficialRatesProvider.combine(euro: Self.euro, tenge: nil, cachedTengePerEuro: nil)
        }
    }

    @Test("with the ECB down, the bank's table alone; with both down, an error")
    func fallsBackToTheBank() async throws {
        let down = CurrencyProviderError.networkError(NSError(domain: "test", code: 1))
        let bankOnly = OfficialRatesProvider(
            ecb: StubProvider(name: "ecb", result: .failure(down)),
            nationalBank: StubProvider(name: "nbk", result: .success(Self.tenge)),
            cachedTengePerEuro: { nil }
        )
        let rates = try await bankOnly.fetchRates(on: nil)
        #expect(rates.providerName == "nbk")
        #expect(rates.rates["USD"] == 501)

        let both = OfficialRatesProvider(
            ecb: StubProvider(name: "ecb", result: .success(Self.euro)),
            nationalBank: StubProvider(name: "nbk", result: .success(Self.tenge)),
            cachedTengePerEuro: { nil }
        )
        #expect(try await both.fetchRates(on: nil).providerName == "ecb+nbk")

        let none = OfficialRatesProvider(
            ecb: StubProvider(name: "ecb", result: .failure(down)),
            nationalBank: StubProvider(name: "nbk", result: .failure(down)),
            cachedTengePerEuro: { 550 }
        )
        await #expect(throws: CurrencyProviderError.self) {
            _ = try await none.fetchRates(on: nil)
        }
    }

    @Test("the store keeps the combined table in tenge")
    func normalizesIntoTheStoresPivot() throws {
        let rates = try OfficialRatesProvider.combine(euro: Self.euro, tenge: Self.tenge, cachedTengePerEuro: nil)
        let normalized = try #require(rates.normalized(toPivot: "KZT"))
        #expect(Self.close(normalized["KRW"], 540 / 1500.0))
    }
}
