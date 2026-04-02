//
//  Formatting.swift
//  AIFinanceManager
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
        return currencySymbols[currency.uppercased()] ?? currency
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
}
