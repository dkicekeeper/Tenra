//
//  FormattingTests.swift
//  AIFinanceManagerTests
//
//  Created on 2024
//  REFACTORED 2026-02-11: Added tests for smart decimal handling
//

import Testing
@testable import AIFinanceManager

struct FormattingTests {

    @Test("Format currency with USD")
    func testFormatCurrencyUSD() {
        let result = Formatting.formatCurrency(1234.56, currency: "USD")
        #expect(result.contains("1 234.56"))
        #expect(result.contains("$"))
    }

    @Test("Format currency with EUR")
    func testFormatCurrencyEUR() {
        let result = Formatting.formatCurrency(999.99, currency: "EUR")
        #expect(result.contains("999.99"))
        #expect(result.contains("€"))
    }

    @Test("Format zero amount - always shows decimals")
    func testFormatZero() {
        let result = Formatting.formatCurrency(0.0, currency: "USD")
        #expect(result.contains("0.00"))
    }

    @Test("Format large amount")
    func testFormatLargeAmount() {
        let result = Formatting.formatCurrency(1234567.89, currency: "USD")
        #expect(result.contains("1 234 567.89"))
    }

    @Test("Format negative amount")
    func testFormatNegative() {
        let result = Formatting.formatCurrency(-100.50, currency: "USD")
        #expect(result.contains("-"))
        #expect(result.contains("100.50"))
    }

    // NEW: Tests for formatCurrencySmart
    @Test("Smart format - whole number without decimals")
    func testSmartFormatWholeNumber() {
        let result = Formatting.formatCurrencySmart(1000.00, currency: "KZT", showDecimalsWhenZero: false)
        #expect(result == "1 000 ₸")
    }

    @Test("Smart format - with decimals")
    func testSmartFormatWithDecimals() {
        let result = Formatting.formatCurrencySmart(1234.56, currency: "USD", showDecimalsWhenZero: false)
        #expect(result == "1 234.56 $")
    }

    @Test("Smart format - force show decimals when zero")
    func testSmartFormatForceDecimals() {
        let result = Formatting.formatCurrencySmart(1000.00, currency: "KZT", showDecimalsWhenZero: true)
        #expect(result == "1 000.00 ₸")
    }

    @Test("Currency symbol lookup")
    func testCurrencySymbol() {
        #expect(Formatting.currencySymbol(for: "USD") == "$")
        #expect(Formatting.currencySymbol(for: "EUR") == "€")
        #expect(Formatting.currencySymbol(for: "KZT") == "₸")
        #expect(Formatting.currencySymbol(for: "RUB") == "₽")
        #expect(Formatting.currencySymbol(for: "GBP") == "£")
    }
}
