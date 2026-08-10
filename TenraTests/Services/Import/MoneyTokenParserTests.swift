//
//  MoneyTokenParserTests.swift
//  TenraTests
//
//  Pins amount/currency extraction from raw statement and receipt cells.
//

import Testing
@testable import Tenra

struct MoneyTokenParserTests {

    @Test("plain and space-grouped amounts parse")
    func plainAmounts() {
        #expect(MoneyTokenParser.parse("2500")?.amount == 2500)
        #expect(MoneyTokenParser.parse("2 500")?.amount == 2500)
        // Non-breaking space (U+00A0) and thin space (U+2009) are what PDF
        // generators actually emit for digit grouping.
        #expect(MoneyTokenParser.parse("2\u{00A0}500,00")?.amount == 2500)
        #expect(MoneyTokenParser.parse("2\u{2009}500.00")?.amount == 2500)
    }

    @Test("both decimal separator conventions parse")
    func decimalSeparators() {
        #expect(MoneyTokenParser.parse("1234.56")?.amount == 1234.56)
        #expect(MoneyTokenParser.parse("1234,56")?.amount == 1234.56)
        #expect(MoneyTokenParser.parse("1,234.56")?.amount == 1234.56)
        #expect(MoneyTokenParser.parse("1.234,56")?.amount == 1234.56)
    }

    @Test("negative forms are detected without losing magnitude")
    func negatives() {
        let minus = MoneyTokenParser.parse("-1 200,00")
        #expect(minus?.amount == 1200)
        #expect(minus?.isNegative == true)

        // U+2212 MINUS SIGN, which banks use instead of ASCII hyphen.
        let unicodeMinus = MoneyTokenParser.parse("\u{2212}1200")
        #expect(unicodeMinus?.isNegative == true)

        let parens = MoneyTokenParser.parse("(1 200,00)")
        #expect(parens?.amount == 1200)
        #expect(parens?.isNegative == true)
    }

    @Test("ISO codes and symbols resolve to a currency")
    func currencies() {
        #expect(MoneyTokenParser.parse("2 500 KZT")?.currency == "KZT")
        #expect(MoneyTokenParser.parse("USD 40.00")?.currency == "USD")
        #expect(MoneyTokenParser.parse("$40.00")?.currency == "USD")
        #expect(MoneyTokenParser.parse("40,00 €")?.currency == "EUR")
        #expect(MoneyTokenParser.parse("¥1200")?.currency == "JPY")
        #expect(MoneyTokenParser.parse("₸2500")?.currency == "KZT")
        // No currency marker means no guess. The caller supplies a default.
        #expect(MoneyTokenParser.parse("2500")?.currency == nil)
    }

    @Test("non-money tokens return nil")
    func nonMoney() {
        #expect(MoneyTokenParser.parse("") == nil)
        #expect(MoneyTokenParser.parse("Purchase") == nil)
        #expect(MoneyTokenParser.parse("-") == nil)
        // A date must never be read as an amount.
        #expect(MoneyTokenParser.parse("08.01.2026") == nil)
    }
}
