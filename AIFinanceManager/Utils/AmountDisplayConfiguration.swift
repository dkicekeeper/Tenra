//
//  AmountDisplayConfiguration.swift
//  AIFinanceManager
//
//  Created on 2026-02-11
//  Centralized configuration for amount display formatting
//

import Foundation

/// Централизованная конфигурация для отображения денежных сумм
struct AmountDisplayConfiguration {
    /// Показывать ли сотые, если они равны нулю
    /// - true: всегда показывать (1000.00)
    /// - false: скрывать если ноль (1000)
    var showDecimalsWhenZero: Bool = false

    /// Прозрачность дробной части (0.0...1.0)
    var decimalOpacity: Double = 0.5

    /// Разделитель тысяч
    var thousandsSeparator: String = " "

    /// Десятичный разделитель
    var decimalSeparator: String = "."

    /// Минимальное количество знаков после запятой
    var minimumFractionDigits: Int = 2

    /// Максимальное количество знаков после запятой
    var maximumFractionDigits: Int = 2

    // MARK: - Shared Instance

    /// Глобальный экземпляр конфигурации.
    /// Замена всего экземпляра или изменение любого свойства
    /// автоматически инвалидирует кэшированный форматтер.
    nonisolated(unsafe) static var shared = AmountDisplayConfiguration() {
        didSet { _cachedFormatter = nil }
    }

    // MARK: - Cached Formatter

    /// Кэшированный форматтер — пересоздаётся только при изменении `shared`.
    /// Используй в hot path (List, ForEach и т.п.).
    private nonisolated(unsafe) static var _cachedFormatter: NumberFormatter?

    nonisolated static var formatter: NumberFormatter {
        if let cached = _cachedFormatter { return cached }
        let f = shared.makeNumberFormatter()
        _cachedFormatter = f
        return f
    }

    // MARK: - Factory

    /// Создаёт новый `NumberFormatter` на основе текущих настроек.
    /// В hot path используй `AmountDisplayConfiguration.formatter` — он кэширован.
    nonisolated func makeNumberFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = thousandsSeparator
        f.decimalSeparator = decimalSeparator
        f.minimumFractionDigits = minimumFractionDigits
        f.maximumFractionDigits = maximumFractionDigits
        f.usesGroupingSeparator = true
        return f
    }
}
