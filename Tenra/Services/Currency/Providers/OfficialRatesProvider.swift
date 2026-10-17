//
//  OfficialRatesProvider.swift
//  Tenra
//
//  The fallback when the CDN tables are out of reach: official reference rates. The ECB's
//  euro table (about 30 currencies, the won, the yen, the lira and the real among them) is put
//  into tenge, the store's pivot, through the National Bank of Kazakhstan's euro rate, and the
//  bank's currencies the ECB lacks (rouble, som, sum) are added. With the bank down, the euro
//  rate the cache already holds anchors the table: pairs without the tenge stay exact, pairs
//  with it are as old as that rate. With the ECB down, the bank's table alone.
//

import Foundation

nonisolated final class OfficialRatesProvider: CurrencyRateProvider {
    let name = "ecb+nbk"

    private let ecb: any CurrencyRateProvider
    private let nationalBank: any CurrencyRateProvider
    /// Tenge per euro in the cache, stale or not: the anchor while the bank is down.
    private let cachedTengePerEuro: @Sendable () -> Double?

    init(
        ecb: any CurrencyRateProvider = ECBCurrencyProvider(),
        nationalBank: any CurrencyRateProvider = NationalBankKZProvider(),
        cachedTengePerEuro: @escaping @Sendable () -> Double? = { CurrencyRateStore.shared.currentRate(for: "EUR") }
    ) {
        self.ecb = ecb
        self.nationalBank = nationalBank
        self.cachedTengePerEuro = cachedTengePerEuro
    }

    func fetchRates(on date: Date?) async throws -> ExchangeRates {
        async let euroTable = ecb.fetchRates(on: date)
        async let tengeTable = nationalBank.fetchRates(on: date)
        let tenge = try? await tengeTable
        let euro: ExchangeRates
        do {
            euro = try await euroTable
        } catch {
            if let tenge { return tenge }
            throw error
        }
        return try Self.combine(euro: euro, tenge: tenge, cachedTengePerEuro: cachedTengePerEuro())
    }

    /// The ECB's table in tenge, `rates[X] = tenge per euro × euro per X`, over the bank's own
    /// rates: every currency the ECB quotes comes from its table, so pairs without the tenge
    /// are the ECB's exactly; the bank adds the ones it lacks.
    static func combine(euro: ExchangeRates, tenge: ExchangeRates?, cachedTengePerEuro: Double?) throws -> ExchangeRates {
        guard euro.pivot == "EUR" else {
            throw CurrencyProviderError.parseError("ecb table is not in euros")
        }
        let bank = tenge?.pivot == "KZT" ? tenge : nil
        guard let anchor = bank?.rates["EUR"] ?? cachedTengePerEuro, anchor > 0 else {
            if let tenge { return tenge }
            throw CurrencyProviderError.rateNotFound
        }
        var rates = bank?.rates ?? [:]
        for (code, euroPerUnit) in euro.rates where code != "KZT" {
            rates[code] = anchor * euroPerUnit
        }
        rates["EUR"] = anchor
        return ExchangeRates(
            pivot: "KZT",
            rates: rates,
            date: euro.date,
            providerName: bank == nil ? "ecb" : "ecb+nbk"
        )
    }
}
