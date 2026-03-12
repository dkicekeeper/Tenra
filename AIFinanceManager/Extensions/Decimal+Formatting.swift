//
//  Decimal+Formatting.swift
//  AIFinanceManager
//
//  Created on 2026-02-15
//
//  Decimal formatting and calculation utilities

import Foundation

extension Decimal {

    // MARK: - Formatting

    /// Format decimal as currency with symbol
    /// - Parameters:
    ///   - currency: Currency code (e.g., "USD", "EUR")
    ///   - locale: Locale to use for formatting (default: current)
    /// - Returns: Formatted string (e.g., "$1,234.56")
    nonisolated func formatted(as currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = locale
        return formatter.string(from: self as NSNumber) ?? "\(self)"
    }

    /// Format decimal with specified fraction digits
    /// - Parameter fractionDigits: Number of decimal places (default: 2)
    /// - Returns: Formatted string (e.g., "1234.56")
    nonisolated func formatted(fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: self as NSNumber) ?? "\(self)"
    }

    // MARK: - Calculations

    /// Round to specified decimal places
    /// - Parameter places: Number of decimal places
    /// - Returns: Rounded decimal
    nonisolated func rounded(toPlaces places: Int) -> Decimal {
        var result = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, places, .plain)
        return rounded
    }

    /// Round to 2 decimal places (common for currencies)
    nonisolated var roundedToCurrency: Decimal {
        rounded(toPlaces: 2)
    }

    /// Absolute value
    nonisolated var abs: Decimal {
        self < 0 ? -self : self
    }

    // MARK: - Conversions

    /// Convert to Double (use with caution for precision-sensitive operations)
    nonisolated var doubleValue: Double {
        (self as NSDecimalNumber).doubleValue
    }

    /// Convert to String
    nonisolated var stringValue: String {
        "\(self)"
    }

    // MARK: - Comparisons

    /// Check if decimal is positive
    nonisolated var isPositive: Bool {
        self > 0
    }

    /// Check if decimal is negative
    nonisolated var isNegative: Bool {
        self < 0
    }

    /// Check if decimal is zero
    nonisolated var isZero: Bool {
        self == 0
    }

    // MARK: - Operators

    /// Calculate percentage of a value
    /// - Parameter percent: Percentage (e.g., 15 for 15%)
    /// - Returns: Calculated amount
    nonisolated func percentage(_ percent: Decimal) -> Decimal {
        (self * percent / 100).roundedToCurrency
    }

    /// Add percentage to value
    /// - Parameter percent: Percentage to add (e.g., 15 for 15%)
    /// - Returns: Value with percentage added
    nonisolated func adding(percentage percent: Decimal) -> Decimal {
        (self + percentage(percent)).roundedToCurrency
    }

    /// Subtract percentage from value
    /// - Parameter percent: Percentage to subtract (e.g., 15 for 15%)
    /// - Returns: Value with percentage subtracted
    nonisolated func subtracting(percentage percent: Decimal) -> Decimal {
        (self - percentage(percent)).roundedToCurrency
    }
}
