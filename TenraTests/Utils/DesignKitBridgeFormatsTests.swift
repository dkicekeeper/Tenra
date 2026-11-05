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

    // MARK: - Regressions of DesignKit 8.8.1 (grouping without the device's locale, the space
    // after a symbol with a letter). Each resolves a region's formats as Settings › Formats does.

    private func applyRegion(_ identifier: String, _ edit: (inout FormatChoices) -> Void = { _ in }) {
        var choices = FormatChoices()
        edit(&choices)
        DesignKitBridge.apply(FormatPreferences.resolve(choices, locale: Locale(identifier: identifier)))
    }

    /// Spain groups from 1 000 in Tenra, though es_ES's own rule leaves "1234,56" ungrouped.
    @Test func spanishRegionGroupsFromAThousand() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }

        applyRegion("es_ES") { $0.separators = .spaceComma }
        #expect(Formatting.formatCurrencySmart(1234.56, currency: "EUR") == "1\u{00A0}234,56 €")

        applyRegion("es_ES")
        #expect(Formatting.formatCurrencySmart(1234.56, currency: "EUR") == "1.234,56 €")
    }

    /// India: "1,234,567.80" groups by 3 once commaDot is chosen; the region's own format keeps
    /// the lakh ("12,34,567.80"). The symbol goes first there: "₹" in most app languages, "INR"
    /// (with its space) in es.
    @Test func indianRegionGroupsByThreeWithCommaDot() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }
        let rupee = Formatting.currencySymbol(for: "INR")
        let before = rupee.contains { $0.isLetter } ? rupee + "\u{00A0}" : rupee

        applyRegion("en_IN") { $0.separators = .commaDot }
        #expect(Formatting.formatCurrencySmart(1_234_567.8, currency: "INR") == before + "1,234,567.80")

        applyRegion("en_IN")
        #expect(Formatting.formatCurrencySmart(1_234_567.8, currency: "INR") == before + "12,34,567.80")
    }

    /// A symbol with a letter keeps a no-break space before the number.
    @Test func swissFrancBeforeTheNumber() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }

        applyRegion("de_CH") {
            $0.separators = .apostropheDot
            $0.symbol = .before
        }

        #expect(Formatting.formatCurrencySmart(1234.5, currency: "CHF") == "CHF\u{00A0}1\u{2019}234.50")
        #expect(Formatting.formatCurrencySmart(-1234.5, currency: "CHF") == "-CHF\u{00A0}1\u{2019}234.50")
    }

    /// Brazil's region puts "R$" first, with a space: "R$ 1.234,56". The symbol is the app
    /// language's ("R$" in most, "BRL" in es); either has letters, so the space stays.
    @Test func brazilianRealBeforeTheNumber() {
        let saved = AmountDisplayConfiguration.shared
        defer { AmountDisplayConfiguration.shared = saved }
        let real = Formatting.currencySymbol(for: "BRL")

        applyRegion("pt_BR")

        #expect(AmountDisplayConfiguration.shared.symbolPosition == .before)
        #expect(Formatting.formatCurrencySmart(1234.56, currency: "BRL") == real + "\u{00A0}1.234,56")
        #expect(Formatting.formatCurrencySmart(-1234.56, currency: "BRL") == "-" + real + "\u{00A0}1.234,56")
        #expect(Formatting.hiddenAmount(currency: "BRL") == real + "\u{00A0}••••")
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
