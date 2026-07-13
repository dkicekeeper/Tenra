//
//  CSVParseAmountTests.swift
//  TenraTests
//
//  Phase 1 localization (de): CSV files mix EU and US number conventions.
//  The old parseAmount blindly replaced "," with "." — "1.234,56" became
//  "1.234.56" → nil (row silently dropped), and "1,234.56" broke the same
//  way. These pin the locale-tolerant heuristic:
//    - both separators present → the LAST one is decimal, the other grouping
//    - single separator + exactly 3 trailing digits → grouping
//    - otherwise → decimal
//

import Testing
import Foundation
@testable import Tenra

struct CSVParseAmountTests {

    private let service = CSVValidationService(headers: [])

    @Test("plain decimal forms parse unchanged")
    func plainDecimals() {
        #expect(service.parseAmount("1234.56") == 1234.56)
        #expect(service.parseAmount("1234,56") == 1234.56)
        #expect(service.parseAmount("12,5") == 12.5)
        #expect(service.parseAmount("0,99") == 0.99)
        #expect(service.parseAmount("500") == 500)
    }

    @Test("German format: dot grouping, comma decimal")
    func germanFormat() {
        #expect(service.parseAmount("1.234,56") == 1234.56)
        #expect(service.parseAmount("1.234.567,89") == 1_234_567.89)
    }

    @Test("US format: comma grouping, dot decimal")
    func usFormat() {
        #expect(service.parseAmount("1,234.56") == 1234.56)
        #expect(service.parseAmount("1,234,567.89") == 1_234_567.89)
    }

    @Test("space / NBSP / narrow-NBSP / apostrophe group separators")
    func spaceGrouping() {
        #expect(service.parseAmount("1 234,56") == 1234.56)
        #expect(service.parseAmount("1\u{00A0}234,56") == 1234.56)
        #expect(service.parseAmount("1\u{202F}234,56") == 1234.56)
        #expect(service.parseAmount("1'234.56") == 1234.56)
    }

    @Test("single separator followed by exactly 3 digits is grouping")
    func threeDigitTailIsGrouping() {
        #expect(service.parseAmount("1,234") == 1234)
        #expect(service.parseAmount("1.234") == 1234)
        #expect(service.parseAmount("12.345.678") == 12_345_678)
    }

    @Test("negative amounts keep their sign")
    func negativeAmounts() {
        #expect(service.parseAmount("-1.234,56") == -1234.56)
        #expect(service.parseAmount("-12,5") == -12.5)
    }

    @Test("garbage and empty input → nil")
    func invalidInput() {
        #expect(service.parseAmount("") == nil)
        #expect(service.parseAmount("abc") == nil)
    }
}
