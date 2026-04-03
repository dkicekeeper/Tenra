//
//  CurrencyInfo.swift
//  Tenra
//

import Foundation

/// Lightweight currency descriptor built from iOS Locale APIs.
/// Name and symbol are localized automatically via Foundation.
struct CurrencyInfo: Identifiable, Sendable, Equatable {
    let code: String   // "USD"
    let name: String   // "Доллар США" / "US Dollar"
    let symbol: String // "$"

    var id: String { code }

    // MARK: - Static Builders

    /// All ISO currencies sorted A-Z by localized name.
    /// Computed once per app launch (locale doesn't change at runtime).
    nonisolated static let allCurrencies: [CurrencyInfo] = {
        let locale = Locale.current
        let symbolExtractor = NumberFormatter()
        symbolExtractor.numberStyle = .currency
        symbolExtractor.maximumFractionDigits = 0
        symbolExtractor.minimumFractionDigits = 0

        var seen = Set<String>()
        var result: [CurrencyInfo] = []

        for isoCurrency in Locale.Currency.isoCurrencies {
            let code = isoCurrency.identifier
            guard !seen.contains(code) else { continue }
            seen.insert(code)

            let name = locale.localizedString(forCurrencyCode: code) ?? code
            guard name != code || code.count == 3 else { continue }

            symbolExtractor.currencyCode = code
            let formatted = symbolExtractor.string(from: 0) ?? code
            let symbol = formatted
                .replacingOccurrences(of: "0", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .trimmingCharacters(in: .whitespaces)

            let finalSymbol = symbol.isEmpty ? code : symbol

            result.append(CurrencyInfo(code: code, name: name, symbol: finalSymbol))
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Top-3 "popular" currencies: device regional + USD + EUR (deduplicated).
    nonisolated static let popularCurrencies: [CurrencyInfo] = {
        let regionalCode = Locale.current.currency?.identifier ?? "KZT"
        var codes: [String] = [regionalCode]
        if regionalCode != "USD" { codes.append("USD") }
        if regionalCode != "EUR" { codes.append("EUR") }

        let lookup = Dictionary(uniqueKeysWithValues: allCurrencies.map { ($0.code, $0) })
        return codes.compactMap { lookup[$0] }
    }()

    /// Look up a single CurrencyInfo by code. O(1) after first access.
    nonisolated static func find(_ code: String) -> CurrencyInfo? {
        lookupTable[code]
    }

    private nonisolated static let lookupTable: [String: CurrencyInfo] = {
        Dictionary(uniqueKeysWithValues: allCurrencies.map { ($0.code, $0) })
    }()
}
