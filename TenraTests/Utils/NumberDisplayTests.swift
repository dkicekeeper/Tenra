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
