//
//  MoneyTokenParser.swift
//  Tenra
//
//  Extracts an amount plus an optional currency from an arbitrary statement or
//  receipt cell. Replaces the five-currency whitelist and the hardcoded "KZT"
//  default in the old StatementTextParser.
//

import Foundation

nonisolated enum MoneyTokenParser {

    struct ParsedMoney: Sendable, Equatable {
        /// Always the absolute value. Direction lives in `isNegative`.
        let amount: Double
        /// ISO 4217 code when the token carried one, otherwise nil.
        let currency: String?
        let isNegative: Bool
    }

    /// Currency symbols that map unambiguously to one ISO code.
    private static let symbolToCode: [Character: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₸": "KZT",
        "₽": "RUB", "₴": "UAH", "₺": "TRY", "₩": "KRW", "₹": "INR",
        "₪": "ILS", "₫": "VND", "฿": "THB", "₦": "NGN", "₱": "PHP"
    ]

    /// All whitespace variants PDF generators use for digit grouping.
    private static let groupingSpaces: Set<Character> = [
        " ", "\u{00A0}", "\u{2009}", "\u{202F}", "\u{2007}", "'", "\u{2019}"
    ]

    static func parse(_ token: String) -> ParsedMoney? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A date is never an amount. Guard first so "08.01.2026" cannot become
        // 8.012026 through the grouping-separator logic below.
        if DateTokenParser.looksLikeDate(trimmed) { return nil }

        let isNegative = trimmed.hasPrefix("-")
            || trimmed.hasPrefix("\u{2212}")
            || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))

        let currency = detectCurrency(in: trimmed)

        // Keep digits and the two separator characters; drop everything else.
        var digits = ""
        for character in trimmed {
            if character.isNumber || character == "." || character == "," {
                digits.append(character)
            } else if groupingSpaces.contains(character), !digits.isEmpty {
                // A grouping space inside a number is dropped silently.
                continue
            }
        }
        guard digits.contains(where: \.isNumber) else { return nil }

        guard let magnitude = Double(normalizeSeparators(digits)) else { return nil }
        return ParsedMoney(amount: magnitude, currency: currency, isNegative: isNegative)
    }

    static func looksLikeMoney(_ token: String) -> Bool {
        parse(token) != nil
    }

    /// Resolves which of "." and "," is the decimal separator, then strips the
    /// other. The last-occurring separator with 1-2 trailing digits wins; if
    /// both look like grouping, everything is grouping.
    private static func normalizeSeparators(_ digits: String) -> String {
        let lastDot = digits.lastIndex(of: ".")
        let lastComma = digits.lastIndex(of: ",")

        let decimalIndex: String.Index?
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            decimalIndex = dot > comma ? dot : comma
        case let (dot?, nil):
            decimalIndex = dot
        case let (nil, comma?):
            decimalIndex = comma
        case (nil, nil):
            return digits
        }

        guard let separatorIndex = decimalIndex else { return digits }
        let fractionDigits = digits.distance(from: digits.index(after: separatorIndex),
                                             to: digits.endIndex)
        // 1 or 2 trailing digits means a decimal separator. 3 means grouping
        // ("1.234" is one thousand two hundred thirty four, not 1.234).
        guard fractionDigits == 1 || fractionDigits == 2 else {
            return digits.filter(\.isNumber)
        }

        let integerPart = digits[digits.startIndex..<separatorIndex].filter(\.isNumber)
        let fractionPart = digits[digits.index(after: separatorIndex)...].filter(\.isNumber)
        return "\(integerPart).\(fractionPart)"
    }

    private static func detectCurrency(in token: String) -> String? {
        for character in token {
            if let code = symbolToCode[character] { return code }
        }
        // ISO code as a standalone uppercase 3-letter run.
        let uppercased = token.uppercased()
        for match in uppercased.matches(of: /\b([A-Z]{3})\b/) {
            let code = String(match.1)
            if isoCodes.contains(code) { return code }
        }
        return nil
    }

    /// ISO 4217 codes the app can actually hold. Kept in sync with the currency
    /// list in Tenra/Utils/ (see docs/domains/currency.md).
    private static let isoCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CNY", "CHF", "CAD", "AUD", "NZD",
        "KZT", "RUB", "UAH", "TRY", "KRW", "INR", "BRL", "MXN", "ARS",
        "PLN", "CZK", "HUF", "SEK", "NOK", "DKK", "AED", "SAR", "ILS",
        "THB", "VND", "IDR", "MYR", "SGD", "HKD", "PHP", "NGN", "ZAR",
        "EGP", "GEL", "AMD", "AZN", "UZS", "KGS", "TJS", "BYN", "MDL"
    ]
}
