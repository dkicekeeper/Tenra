//
//  Formatting.swift
//  Tenra
//
//  Created on 2024
//  REFACTORED 2026-02-11: Added smart decimal handling with AmountDisplayConfiguration
//

import Foundation

nonisolated struct Formatting {
    static let currencySymbols: [String: String] = [
        "KZT": "₸",
        "USD": "$",
        "EUR": "€",
        "RUB": "₽",
        "GBP": "£",
        "CNY": "¥",
        "JPY": "¥"
    ]

    /// Получает символ валюты по коду
    /// - Parameter currency: Код валюты (например, "USD", "KZT")
    /// - Returns: Символ валюты (например, "$", "₸") или код валюты, если символ не найден
    static func currencySymbol(for currency: String) -> String {
        if let symbol = currencySymbols[currency.uppercased()] {
            return symbol
        }
        // Fallback: use CurrencyInfo lookup (covers all ISO currencies)
        if let info = CurrencyInfo.find(currency.uppercased()) {
            return info.symbol
        }
        return currency
    }

    /// Форматирует сумму с символом валюты (старая версия, всегда показывает .00)
    /// - Parameters:
    ///   - amount: Сумма
    ///   - currency: Код валюты
    /// - Returns: Отформатированная строка с символом валюты (например, "1,234.56 $")
    /// - Note: Для обратной совместимости. Используйте formatCurrencySmart() для умной обработки дробной части
    static func formatCurrency(_ amount: Double, currency: String) -> String {
        return formatCurrencySmart(amount, currency: currency, showDecimalsWhenZero: true)
    }

    /// Форматирует сумму с символом валюты с умной обработкой дробной части
    /// - Parameters:
    ///   - amount: Сумма
    ///   - currency: Код валюты
    ///   - showDecimalsWhenZero: Показывать ли .00 для целых чисел (по умолчанию из конфигурации)
    /// - Returns: Отформатированная строка (например, "1 234" или "1 234.56 ₸")
    static func formatCurrencySmart(
        _ amount: Double,
        currency: String,
        showDecimalsWhenZero: Bool = AmountDisplayConfiguration.shared.showDecimalsWhenZero
    ) -> String {
        let symbol = currencySymbol(for: currency)
        let hasDecimals = amount.truncatingRemainder(dividingBy: 1) != 0

        // Hot path: use cached formatter; only allocate a new one for the no-decimals variant
        // (can't mutate the shared cached instance)
        let numberFormatter: NumberFormatter
        if !showDecimalsWhenZero && !hasDecimals {
            let f = AmountDisplayConfiguration.shared.makeNumberFormatter()
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = 0
            numberFormatter = f
        } else {
            numberFormatter = AmountDisplayConfiguration.formatter
        }

        guard let formattedAmount = numberFormatter.string(from: NSNumber(value: amount)) else {
            return String(format: "%.2f %@", amount, symbol)
        }

        return "\(formattedAmount) \(symbol)"
    }

    // MARK: - Compact (abbreviated) amounts

    /// Abbreviated amount with currency symbol — "1.2M ₸", "1,2 млн ₸", "120万 ₸".
    ///
    /// Used ONLY as a fallback by `FormattedAmountText` when the full amount does not fit
    /// its container (see `AmountDisplayPolicy.adaptive`). Never call it to pre-shorten an
    /// amount by hand: a value that fits must always render in full.
    ///
    /// The unit names come from the system compact notation, so they follow the reader's
    /// locale — including languages that group by 10 000 rather than 1 000 (ja 万, ko 억).
    /// A hand-rolled K/M table produces wrong magnitudes there, which is exactly the case
    /// this is meant to serve (currencies counted in hundreds of millions).
    ///
    /// - Parameter maxFractionDigits: `1` → "1.2M", `0` → "1M".
    /// - Parameter locale: injectable for tests; defaults to the reader's locale.
    static func formatCurrencyCompact(
        _ amount: Double,
        currency: String,
        maxFractionDigits: Int = 1,
        locale: Locale = .current
    ) -> String {
        let symbol = currencySymbol(for: currency)
        let style = FloatingPointFormatStyle<Double>
            .number
            .notation(.compactName)
            .precision(.fractionLength(0...max(0, maxFractionDigits)))
            .locale(locale)
        return "\(amount.formatted(style)) \(symbol)"
    }
}
