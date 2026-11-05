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
    /// `signed` writes "+" before a positive value ("+12%"); a negative keeps its minus.
    static func percent(
        _ percentValue: Double,
        fractionDigits: Int = 0,
        signed: Bool = false,
        formats: ResolvedFormats = FormatSettings.snapshot
    ) -> String {
        let text = decimal(percentValue, fractionDigits: fractionDigits...fractionDigits, formats: formats)
        let sign = signed && percentValue > 0 && !text.hasPrefix("-") ? "+" : ""
        return sign + text + "%"
    }

    /// A number with exactly `fractionDigits` fraction digits, grouped thousands and the
    /// chosen separators.
    static func decimal(
        _ value: Double,
        fractionDigits: Int,
        formats: ResolvedFormats = FormatSettings.snapshot
    ) -> String {
        decimal(value, fractionDigits: fractionDigits...fractionDigits, formats: formats)
    }

    /// A number with between `fractionDigits.lowerBound` and `upperBound` fraction digits
    /// (`0...1` drops a zero fraction: 12 reads "12", 12.5 reads "12,5").
    static func decimal(
        _ value: Double,
        fractionDigits: ClosedRange<Int>,
        formats: ResolvedFormats = FormatSettings.snapshot
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = formats.secondaryGroupingSize ?? 0
        formatter.minimumFractionDigits = fractionDigits.lowerBound
        formatter.maximumFractionDigits = fractionDigits.upperBound
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

    /// A whole number with grouped thousands: 1234 reads "1,234" under commaDot.
    static func integer(_ value: Int, formats: ResolvedFormats = FormatSettings.snapshot) -> String {
        decimal(Double(value), fractionDigits: 0, formats: formats)
    }

    /// A file size ("1.2 MB", the backups on Settings): ByteCountFormatter's text with the
    /// chosen marks in place of the locale's.
    static func fileSize(_ bytes: Int64, formats: ResolvedFormats = FormatSettings.snapshot) -> String {
        var marks = AmountDisplayConfiguration()
        marks.decimalSeparator = formats.decimalSeparator
        marks.thousandsSeparator = formats.groupingSeparator
        marks.separatorsOverrideLocale = true
        return Formatting.applyConfiguredSeparators(
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
            locale: .current,
            configuration: marks
        )
    }
}
