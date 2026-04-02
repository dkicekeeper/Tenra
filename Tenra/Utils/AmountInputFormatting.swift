//
//  AmountInputFormatting.swift
//  AIFinanceManager
//
//  Shared static utilities for amount input components.
//  Single source of truth for string cleaning and display formatting
//  used by AmountDigitDisplay (via AmountInputView and AnimatedAmountInput).
//

import SwiftUI

// MARK: - AmountInputFormatting

/// Static formatting utilities shared between amount input components.
///
/// Centralises formatter instances, string cleaning, and display formatting
/// so all amount input components use identical mechanics.
enum AmountInputFormatting {

    // MARK: - Formatter

    /// Primary formatter: groups digits with spaces, up to 2 decimal places.
    /// Used by currency conversion display and other formatted amount contexts.
    static let displayFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.decimalSeparator = "."
        return f
    }()

    // MARK: - String Cleaning

    /// Normalises the decimal separator and strips all non-numeric characters.
    /// Single source of truth — used for both keyboard input and clipboard paste.
    /// Preserves a leading minus sign for negative balances.
    static func cleanAmountString(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let hasLeadingMinus = normalized.first == "-"
        let digits = normalized.filter { $0.isNumber || $0 == "." }
        return hasLeadingMinus ? "-" + digits : digits
    }

    // MARK: - Display Formatting

    /// Converts a raw amount string into a user-facing display string with grouping.
    ///
    /// Rules:
    /// - Empty or zero input → `"0"`
    /// - Non-parseable input → cleaned raw string (preserves typing in progress)
    /// - Valid Decimal → formatted with `displayFormatter`; falls back to `formatLargeNumber`
    static func displayAmount(for text: String) -> String {
        let cleaned = cleanAmountString(text)

        if cleaned.isEmpty { return "0" }

        guard let decimal = Decimal(string: cleaned) else { return cleaned }

        let number = NSDecimalNumber(decimal: decimal)
        if number.compare(NSDecimalNumber.zero) == .orderedSame { return "0" }

        if let formatted = displayFormatter.string(from: number) { return formatted }
        return formatLargeNumber(decimal)
    }

    /// Formats a Decimal that `displayFormatter` could not handle,
    /// grouping the integer part with spaces.
    static func formatLargeNumber(_ decimal: Decimal) -> String {
        if let s = displayFormatter.string(from: NSDecimalNumber(decimal: decimal)) { return s }
        let string = String(describing: decimal)
        guard string.contains(".") else { return groupDigits(string) }
        let parts = string.components(separatedBy: ".")
        return "\(groupDigits(parts[0])).\(parts[1].prefix(2))"
    }

    /// Groups digits in an integer string with space separators every 3 digits.
    static func groupDigits(_ s: String) -> String {
        var result = ""
        for (i, char) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { result = " " + result }
            result = String(char) + result
        }
        return result
    }
}
