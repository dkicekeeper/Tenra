//
//  NumberDisplayTests.swift
//  TenraTests
//
//  Percentages and plain decimals in the chosen separators.
//

import Testing
import Foundation
@testable import Tenra

@Suite("NumberDisplay")
struct NumberDisplayTests {

    private func formats(decimal: String, grouping: String, secondary: Int? = nil) -> ResolvedFormats {
        ResolvedFormats(
            dateStyle: .words, firstWeekday: 2,
            decimalSeparator: decimal, groupingSeparator: grouping,
            secondaryGroupingSize: secondary, symbol: .after, cents: .whenPresent)
    }

    private let spaceComma = ResolvedFormats(
        dateStyle: .words, firstWeekday: 2, decimalSeparator: ",", groupingSeparator: "\u{00A0}",
        secondaryGroupingSize: nil, symbol: .after, cents: .whenPresent)

    @Test func percentWithOneFractionDigitUsesTheDecimalSeparator() {
        #expect(NumberDisplay.percent(34.2, fractionDigits: 1, formats: formats(decimal: ",", grouping: ".")) == "34,2%")
    }

    @Test func percentDefaultsToWholeNumbersWithoutASpace() {
        #expect(NumberDisplay.percent(34.2, formats: spaceComma) == "34%")
    }

    @Test func decimalGroupsThousands() {
        #expect(NumberDisplay.decimal(1234.5, fractionDigits: 2, formats: formats(decimal: ".", grouping: ",")) == "1,234.50")
    }

    @Test func decimalHonoursSecondaryGrouping() {
        #expect(NumberDisplay.decimal(1234567, fractionDigits: 0, formats: formats(decimal: ".", grouping: ",", secondary: 2)) == "12,34,567")
    }

    @Test func negativePercentKeepsItsSign() {
        #expect(NumberDisplay.percent(-8.56, fractionDigits: 1, formats: formats(decimal: ".", grouping: ",")) == "-8.6%")
    }
}

@Suite("NumberDisplay variants")
struct NumberDisplayVariantTests {
    private func formats(_ decimal: String, _ grouping: String) -> ResolvedFormats {
        ResolvedFormats(
            dateStyle: .words, firstWeekday: 2, decimalSeparator: decimal, groupingSeparator: grouping,
            secondaryGroupingSize: nil, symbol: .after, cents: .whenPresent)
    }

    @Test func rangeDropsAZeroFraction() {
        let dotComma = formats(",", ".")
        let spaceComma = formats(",", "\u{00A0}")
        #expect(NumberDisplay.decimal(12.0, fractionDigits: 0...1, formats: dotComma) == "12")
        #expect(NumberDisplay.decimal(12.5, fractionDigits: 0...1, formats: dotComma) == "12,5")
        #expect(NumberDisplay.decimal(12.0, fractionDigits: 0...1, formats: spaceComma) == "12")
        #expect(NumberDisplay.decimal(12.5, fractionDigits: 0...1, formats: spaceComma) == "12,5")
    }

    @Test func integerGroupsThousands() {
        #expect(NumberDisplay.integer(1234, formats: formats(".", ",")) == "1,234")
        #expect(NumberDisplay.integer(999, formats: formats(".", ",")) == "999")
    }

    @Test func signedPercentAlwaysShowsPlusForPositive() {
        let f = formats(".", ",")
        #expect(NumberDisplay.percent(12, signed: true, formats: f) == "+12%")
        // A negative keeps the ASCII hyphen-minus the formatter writes.
        #expect(NumberDisplay.percent(-8, signed: true, formats: f) == "-8%")
        #expect(NumberDisplay.percent(0, signed: true, formats: f) == "0%")
        #expect(NumberDisplay.percent(12, formats: f) == "12%")
    }

    /// The backups' sizes on Settings: ByteCountFormatter writes the locale's mark ("1.2 MB",
    /// "1,2 МБ"); the chosen one replaces it, whatever the test host's locale.
    @Test func fileSizeUsesTheChosenDecimalSeparator() {
        let text = NumberDisplay.fileSize(1_234_567, formats: formats("x", "y"))
        #expect(text.contains("1x2"))
        #expect(!text.contains("1.2") && !text.contains("1,2"))
    }
}
