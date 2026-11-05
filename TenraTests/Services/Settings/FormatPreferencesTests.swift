//
//  FormatPreferencesTests.swift
//  TenraTests
//
//  Pins how the region and the person's choices resolve into dates and amounts formats.
//

import Testing
import Foundation
@testable import Tenra

struct FormatPreferencesTests {

    @Test("Kazakhstan in Russian: words, Monday, a comma and a no-break space, the symbol after")
    func kazakhstanInRussian() {
        let region = FormatPreferences.region(for: Locale(identifier: "ru_KZ"))
        #expect(region == ResolvedFormats(
            dateStyle: .words, firstWeekday: 2,
            decimalSeparator: ",", groupingSeparator: "\u{00A0}", secondaryGroupingSize: nil,
            symbol: .after, cents: .whenPresent))
    }

    @Test("English in Kazakhstan keeps the symbol after the amount")
    func englishInKazakhstanKeepsSymbolAfter() {
        #expect(FormatPreferences.region(for: Locale(identifier: "en_KZ")).symbol == .after)
    }

    @Test("The United States: Sunday, a point and a comma, the symbol before")
    func unitedStates() {
        let region = FormatPreferences.region(for: Locale(identifier: "en_US"))
        #expect(region.firstWeekday == 1)
        #expect(region.decimalSeparator == ".")
        #expect(region.groupingSeparator == ",")
        #expect(region.symbol == .before)
    }

    @Test("Germany: a comma and a point, the symbol after")
    func germany() {
        let region = FormatPreferences.region(for: Locale(identifier: "de_DE"))
        #expect(region.decimalSeparator == ",")
        #expect(region.groupingSeparator == ".")
        #expect(region.symbol == .after)
    }

    @Test("India groups by two after the first three and offers its own format")
    func india() {
        let region = FormatPreferences.region(for: Locale(identifier: "en_IN"))
        #expect(region.secondaryGroupingSize == 2)
        #expect(FormatPreferences.separatorOptions(region: region).contains(.region))
    }

    @Test("France's narrow no-break space counts as a space: no extra region option")
    func franceNarrowSpaceIsSpace() {
        let region = FormatPreferences.region(for: Locale(identifier: "fr_FR"))
        #expect(!FormatPreferences.separatorOptions(region: region).contains(.region))
    }

    @Test("Switzerland's ASCII apostrophe counts as the apostrophe format")
    func switzerlandApostropheIsApostrophe() {
        let region = FormatPreferences.region(for: Locale(identifier: "de_CH"))
        #expect(!FormatPreferences.separatorOptions(region: region).contains(.region))
    }

    @Test("One choice stays, the rest follows the region")
    func choiceStaysOthersFollowRegion() {
        let choices = FormatChoices(separators: .commaDot)
        let kazakhstan = FormatPreferences.resolve(choices, locale: Locale(identifier: "ru_KZ"))
        #expect(kazakhstan.decimalSeparator == ".")
        #expect(kazakhstan.groupingSeparator == ",")
        #expect(kazakhstan.firstWeekday == 2)
        let america = FormatPreferences.resolve(choices, locale: Locale(identifier: "en_US"))
        #expect(america.decimalSeparator == ".")
        #expect(america.groupingSeparator == ",")
        #expect(america.firstWeekday == 1)
    }

    @Test("Week start options: Monday, Sunday, and the region's own day when it is another")
    func weekStartOptions() {
        #expect(FormatPreferences.weekStartOptions(regionFirstWeekday: 2) == [2, 1])
        #expect(FormatPreferences.weekStartOptions(regionFirstWeekday: 1) == [2, 1])
        #expect(FormatPreferences.weekStartOptions(regionFirstWeekday: 7) == [2, 1, 7])
    }
}
