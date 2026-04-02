//
//  AmountFormatterTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026
//

import Testing
import Foundation
@testable import AIFinanceManager

struct AmountFormatterTests {

    @Test("Parse valid decimal amount")
    func testParseValidAmount() {
        let result = AmountFormatter.parse("1234.56")
        #expect(result == Decimal(string: "1234.56"))
    }

    @Test("Parse amount with spaces")
    func testParseAmountWithSpaces() {
        let result = AmountFormatter.parse("1 234 567.89")
        #expect(result == Decimal(string: "1234567.89"))
    }

    @Test("Parse amount with comma as decimal separator")
    func testParseAmountWithComma() {
        let result = AmountFormatter.parse("1234,56")
        #expect(result == Decimal(string: "1234.56"))
    }

    @Test("Parse zero amount")
    func testParseZero() {
        let result = AmountFormatter.parse("0")
        #expect(result == Decimal.zero)
    }

    @Test("Parse invalid amount returns nil")
    func testParseInvalidAmount() {
        let result = AmountFormatter.parse("abc")
        #expect(result == nil)
    }

    @Test("Format decimal for display")
    func testFormatDecimal() {
        let result = AmountFormatter.format(1234567.89)
        #expect(result == "1 234 567.89")
    }

    @Test("Validate valid input")
    func testValidateValidInput() {
        #expect(AmountFormatter.isValidInput("1234.56") == true)
        #expect(AmountFormatter.isValidInput("1 234.56") == true)
        #expect(AmountFormatter.isValidInput("1234,56") == true)
    }

    @Test("Validate invalid input")
    func testValidateInvalidInput() {
        #expect(AmountFormatter.isValidInput("abc") == false)
        #expect(AmountFormatter.isValidInput("12abc34") == false)
    }

    @Test("Validate decimal places")
    func testValidateDecimalPlaces() {
        #expect(AmountFormatter.validateDecimalPlaces("1234.56") == true)
        #expect(AmountFormatter.validateDecimalPlaces("1234.5") == true)
        #expect(AmountFormatter.validateDecimalPlaces("1234.567") == false)
        #expect(AmountFormatter.validateDecimalPlaces("1234") == true)
    }

    // MARK: - validate(_:) — Upper-Bound Tests (SEC-02)

    @Test("Validate: maximum allowed amount is accepted")
    func testValidateMaximumAllowed() {
        // 999,999,999.99 is the upper bound — must return true
        let max = Decimal(string: "999999999.99")!
        #expect(AmountFormatter.validate(max) == true)
    }

    @Test("Validate: amount above maximum is rejected")
    func testValidateAboveMaximum() {
        // 1,000,000,000 exceeds the upper bound — must return false
        let overMax = Decimal(string: "1000000000")!
        #expect(AmountFormatter.validate(overMax) == false)
    }

    @Test("Validate: small positive amount is accepted")
    func testValidateSmallPositive() {
        let small = Decimal(string: "0.01")!
        #expect(AmountFormatter.validate(small) == true)
    }

    @Test("Validate: negative amount is rejected")
    func testValidateNegativeAmount() {
        let negative = Decimal(string: "-1")!
        #expect(AmountFormatter.validate(negative) == false)
    }

    @Test("Validate: 999,999,999.999 (3 decimals) exceeds max — rejected")
    func testValidateThreeDecimalExceedsMax() {
        // validate() checks only upper bound (not decimal places)
        // 999,999,999.999 > 999,999,999.99, so it must return false
        let overMax = Decimal(string: "999999999.999")!
        #expect(AmountFormatter.validate(overMax) == false)
    }
}
