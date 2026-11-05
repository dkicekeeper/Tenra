//
//  DesignKitBridgeFormatsTests.swift
//  TenraTests
//
//  `DesignKitBridge.apply(_:)` carries the chosen formats into DesignKit's amount configuration.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite("DesignKitBridge formats", .serialized, .sharedProcessState)
struct DesignKitBridgeFormatsTests {

    private func formats(
        decimal: String, grouping: String, secondary: Int? = nil,
        symbol: AmountSymbolPosition = .after, cents: CentsDisplay = .whenPresent
    ) -> ResolvedFormats {
        ResolvedFormats(
            dateStyle: .words, firstWeekday: 2,
            decimalSeparator: decimal, groupingSeparator: grouping,
            secondaryGroupingSize: secondary, symbol: symbol, cents: cents)
    }

    @Test func appliesSeparatorsSymbolAndCents() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }

        DesignKitBridge.apply(formats(decimal: ".", grouping: ",", symbol: .before, cents: .never))

        #expect(Formatting.formatCurrencySmart(1234.5, currency: "USD") == "$1,235")
    }

    @Test func copiesEveryDimensionIntoTheConfiguration() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }

        DesignKitBridge.apply(formats(decimal: ",", grouping: ".", secondary: 2, symbol: .before, cents: .always))

        let configuration = AmountDisplayConfiguration.shared
        #expect(configuration.decimalSeparator == ",")
        #expect(configuration.thousandsSeparator == ".")
        #expect(configuration.secondaryGroupingSize == 2)
        #expect(configuration.symbolPosition == .before)
        #expect(configuration.fractions == .always)
        #expect(configuration.separatorsOverrideLocale)
    }

    @Test func abbreviatedAmountsFollowTheChosenSeparatorInACommaLocale() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }

        DesignKitBridge.apply(formats(decimal: ".", grouping: ","))

        let text = Formatting.formatCompactNumber(
            1_250_000, maxFractionDigits: 1,
            locale: Locale(identifier: "de_DE"), configuration: .shared)
        #expect(text.contains("."))
        #expect(!text.contains(","))
    }
}
