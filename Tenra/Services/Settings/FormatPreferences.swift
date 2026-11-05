//
//  FormatPreferences.swift
//  Tenra
//
//  How dates and amounts are written. The region gives every default; a person's choice
//  (`FormatChoices`, nil = as in the region) overrides one dimension at a time.
//

import Foundation

nonisolated enum DateStyle: String, Codable, Sendable, CaseIterable {
    case words, dots, slash, iso
}

nonisolated enum AmountSeparators: String, Codable, Sendable, CaseIterable {
    case spaceComma, commaDot, dotComma, apostropheDot, spaceDot, region
}

nonisolated enum AmountSymbolPosition: String, Codable, Sendable {
    case after, before
}

nonisolated enum CentsDisplay: String, Codable, Sendable, CaseIterable {
    case whenPresent, always, never
}

/// The person's choices; nil = as in the region.
nonisolated struct FormatChoices: Codable, Sendable, Equatable {
    var date: DateStyle?
    var firstWeekday: Int?
    var separators: AmountSeparators?
    var symbol: AmountSymbolPosition?
    var cents: CentsDisplay?
}

nonisolated struct ResolvedFormats: Sendable, Equatable {
    var dateStyle: DateStyle
    var firstWeekday: Int
    var decimalSeparator: String
    var groupingSeparator: String
    var secondaryGroupingSize: Int?
    var symbol: AmountSymbolPosition
    var cents: CentsDisplay
}

nonisolated enum FormatPreferences {

    static func resolve(_ choices: FormatChoices, locale: Locale) -> ResolvedFormats {
        var decimal = locale.decimalSeparator ?? "."
        var grouping = locale.groupingSeparator ?? "\u{00A0}"
        var secondary = secondaryGroupingSize(for: locale)
        if let pair = pair(for: choices.separators) {
            (grouping, decimal) = pair
            secondary = nil
        }
        return ResolvedFormats(
            dateStyle: choices.date ?? .words,
            firstWeekday: choices.firstWeekday ?? locale.calendar.firstWeekday,
            decimalSeparator: decimal,
            groupingSeparator: grouping,
            secondaryGroupingSize: secondary,
            symbol: choices.symbol ?? symbolPosition(regionCode: locale.region?.identifier),
            cents: choices.cents ?? .whenPresent)
    }

    static func region(for locale: Locale) -> ResolvedFormats {
        resolve(FormatChoices(), locale: locale)
    }

    /// Monday and Sunday, plus the region's own first day when it is neither.
    static func weekStartOptions(regionFirstWeekday: Int) -> [Int] {
        var options = [2, 1]
        if !options.contains(regionFirstWeekday) { options.append(regionFirstWeekday) }
        return options
    }

    /// The five named formats, and the region's own only when none of them matches it.
    static func separatorOptions(region: ResolvedFormats) -> [AmountSeparators] {
        var options: [AmountSeparators] = [.spaceComma, .commaDot, .dotComma, .apostropheDot, .spaceDot]
        let matches = region.secondaryGroupingSize == nil && options.contains { option in
            guard let pair = pair(for: option) else { return false }
            return normalized(pair.grouping) == normalized(region.groupingSeparator)
                && pair.decimal == region.decimalSeparator
        }
        if !matches { options.append(.region) }
        return options
    }

    /// Before or after the number, by the region's likely language: the currency format of
    /// `<language>_<region>` starts with the sign when the symbol goes first.
    static func symbolPosition(regionCode: String?) -> AmountSymbolPosition {
        guard let regionCode else { return .after }
        let likely = Locale.Language(identifier: "und-\(regionCode)").maximalIdentifier
        let language = Locale.Language(identifier: likely).languageCode?.identifier ?? "en"
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "\(language)_\(regionCode)")
        formatter.numberStyle = .currency
        let format = formatter.positiveFormat ?? ""
        let first = format.first { !"\u{200E}\u{200F}\u{061C}".contains($0) }
        return first == "¤" ? .before : .after
    }

    // MARK: - Helpers

    private static func pair(for separators: AmountSeparators?) -> (grouping: String, decimal: String)? {
        switch separators {
        case .spaceComma: ("\u{00A0}", ",")
        case .commaDot: (",", ".")
        case .dotComma: (".", ",")
        case .apostropheDot: ("\u{2019}", ".")
        case .spaceDot: ("\u{00A0}", ".")
        case .region, nil: nil
        }
    }

    /// A space, a no-break space and a narrow no-break space are one "space".
    private static func normalized(_ grouping: String) -> String {
        ["\u{00A0}", "\u{202F}", " "].contains(grouping) ? " " : grouping
    }

    private static func secondaryGroupingSize(for locale: Locale) -> Int? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let size = formatter.secondaryGroupingSize
        return size > 0 ? size : nil
    }
}
