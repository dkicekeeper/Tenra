//
//  JsDelivrCurrencyProvider.swift
//  Tenra
//
//  Primary exchange-rate source. Uses the public `@fawazahmed0/currency-api`
//  served via jsDelivr CDN — no API key, no rate limits, ~200 currencies,
//  daily updates.
//
//  Endpoints:
//      Latest:     https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/{base}.json
//      Historical: https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{YYYY-MM-DD}/v1/currencies/{base}.json
//      Fallback:   https://{date}.currency-api.pages.dev/v1/currencies/{base}.json    (Cloudflare mirror)
//
//  Response shape: `{"date": "YYYY-MM-DD", "{base}": {"kzt": 442.5, "eur": 0.93, ...}}`
//  All currency codes are lowercased in the API.
//
//  API convention: `api[base][X] = X per 1 base`. We re-key into convention A
//  (`rates[X] = pivot per 1 X`) by inverting: `rates[X] = 1 / api[base][X]`.
//

import Foundation
import os

nonisolated final class JsDelivrCurrencyProvider: CurrencyRateProvider {
    let name = "jsdelivr"

    /// Currency code used as API base. We pick USD because every other currency
    /// has a USD cross-rate, so we always get a complete table.
    private let apiBase: String

    private let urlSession: URLSession
    private static let logger = Logger(subsystem: "Tenra", category: "JsDelivrCurrencyProvider")

    init(apiBase: String = "USD", urlSession: URLSession = .shared) {
        self.apiBase = apiBase.uppercased()
        self.urlSession = urlSession
    }

    func fetchRates(on date: Date?) async throws -> ExchangeRates {
        let urls = Self.buildURLs(apiBase: apiBase, date: date)

        var lastError: Error?
        for url in urls {
            do {
                let (data, response) = try await urlSession.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    Self.logger.debug("jsdelivr non-2xx: \(http.statusCode, privacy: .public) at \(url.absoluteString, privacy: .public)")
                    lastError = CurrencyProviderError.invalidResponse
                    continue
                }
                return try Self.parse(data: data, apiBase: apiBase, requestedDate: date ?? Date())
            } catch {
                Self.logger.debug("jsdelivr fetch failed at \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                lastError = error
                continue
            }
        }
        throw lastError ?? CurrencyProviderError.invalidResponse
    }

    // MARK: - URL builders (jsDelivr primary + Cloudflare mirror fallback)

    private static func buildURLs(apiBase: String, date: Date?) -> [URL] {
        let baseLower = apiBase.lowercased()
        let datePath: String
        if let date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            datePath = formatter.string(from: date)
        } else {
            datePath = "latest"
        }

        // jsDelivr primary
        let primary = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(datePath)/v1/currencies/\(baseLower).json"
        // Cloudflare mirror (failover)
        let mirror = "https://\(datePath).currency-api.pages.dev/v1/currencies/\(baseLower).json"

        return [primary, mirror].compactMap { URL(string: $0) }
    }

    // MARK: - Parsing

    /// Parses the jsDelivr/Cloudflare response into our normalized `ExchangeRates`.
    /// Inverts every entry so the result is in convention A (`rates[X] = pivot per 1 X`).
    static func parse(data: Data, apiBase: String, requestedDate: Date) throws -> ExchangeRates {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CurrencyProviderError.parseError("root is not a JSON object")
        }

        let baseKey = apiBase.lowercased()
        guard let table = json[baseKey] as? [String: Any] else {
            throw CurrencyProviderError.parseError("missing key '\(baseKey)' in response")
        }

        // API: `table[X] = X per 1 base`  ⇒  `inverted[X] = base per 1 X = 1 / table[X]`
        var inverted: [String: Double] = [:]
        inverted.reserveCapacity(table.count)
        for (code, value) in table {
            guard let raw = (value as? Double) ?? ((value as? NSNumber)?.doubleValue), raw > 0 else {
                continue
            }
            let upper = code.uppercased()
            // Skip if this is the API base itself (it's the pivot — implicit 1.0).
            if upper == apiBase.uppercased() { continue }
            inverted[upper] = 1.0 / raw
        }

        // Optional `date` field in response — fall back to requested date.
        let date: Date
        if let dateString = json["date"] as? String {
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            parser.timeZone = TimeZone(identifier: "UTC")
            date = parser.date(from: dateString) ?? requestedDate
        } else {
            date = requestedDate
        }

        if inverted.isEmpty {
            throw CurrencyProviderError.parseError("response contained no usable rates")
        }

        return ExchangeRates(
            pivot: apiBase.uppercased(),
            rates: inverted,
            date: date,
            providerName: "jsdelivr"
        )
    }
}
