//
//  NumberDisplay.swift
//  Tenra
//
//  Plain numbers (percentages, rates, areas) in the reader's chosen separators, the same
//  marks the amounts use. Money never goes through here: amounts use `FormattedAmountText`
//  / `Formatting.formatCurrencySmart`.
//

import Foundation

nonisolated enum NumberDisplay {

    /// `percentValue` is already a percentage: 34.2 reads "34,2%" (no space before the sign).
    static func percent(
        _ percentValue: Double,
        fractionDigits: Int = 0,
        formats: ResolvedFormats = FormatSettings.snapshot
    ) -> String {
        decimal(percentValue, fractionDigits: fractionDigits, formats: formats) + "%"
    }

    /// A number with exactly `fractionDigits` fraction digits, grouped thousands and the
    /// chosen separators.
    static func decimal(
        _ value: Double,
        fractionDigits: Int,
        formats: ResolvedFormats = FormatSettings.snapshot
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = formats.secondaryGroupingSize ?? 0
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        let plain = formatter.string(from: NSNumber(value: value)) ?? String(value)
        var result = ""
        for character in plain {
            switch character {
            case ",": result += formats.groupingSeparator
            case ".": result += formats.decimalSeparator
            default: result.append(character)
            }
        }
        return result
    }
}
