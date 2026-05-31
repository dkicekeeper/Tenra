//
//  CalculatorInputModelTests.swift
//  TenraTests
//
//  Pins the keypad state machine: button sequences → expression / result / amountText.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite("CalculatorInputModel")
struct CalculatorInputModelTests {

    private func model() -> CalculatorInputModel { CalculatorInputModel() }

    private func type(_ m: CalculatorInputModel, _ digits: String) {
        for ch in digits { m.tapDigit(ch) }
    }

    // MARK: - Digits

    @Test("typing digits builds the expression and amount")
    func typingDigits() {
        let m = model()
        type(m, "123")
        #expect(m.expression == "123")
        #expect(m.amountText == "123")
        #expect(m.hasOperator == false)
    }

    @Test("a leading zero is replaced by the next digit")
    func leadingZeroReplaced() {
        let m = model()
        m.tapDigit("0")
        m.tapDigit("5")
        #expect(m.expression == "5")
    }

    // MARK: - Operators

    @Test("addition sequence evaluates live")
    func additionSequence() {
        let m = model()
        type(m, "1200")
        m.tapOperator(.add)
        type(m, "350")
        #expect(m.expression == "1200+350")
        #expect(m.result == Decimal(1550))
        #expect(m.amountText == "1550")
        #expect(m.hasOperator == true)
    }

    @Test("a leading operator is ignored")
    func leadingOperatorIgnored() {
        let m = model()
        m.tapOperator(.add)
        #expect(m.expression == "")
    }

    @Test("a second operator replaces the pending one")
    func operatorReplacesPending() {
        let m = model()
        type(m, "12")
        m.tapOperator(.add)
        m.tapOperator(.multiply)
        #expect(m.expression == "12*")
    }

    // MARK: - Separator

    @Test("separator adds a decimal point to the current operand")
    func separatorAddsPoint() {
        let m = model()
        m.tapDigit("1")
        m.tapSeparator()
        m.tapDigit("5")
        #expect(m.expression == "1.5")
    }

    @Test("separator on an empty operand inserts a leading zero")
    func separatorOnEmptyOperand() {
        let m = model()
        m.tapSeparator()
        #expect(m.expression == "0.")
    }

    @Test("only one separator per operand")
    func oneSeparatorPerOperand() {
        let m = model()
        type(m, "1")
        m.tapSeparator()
        type(m, "5")
        m.tapSeparator() // ignored
        #expect(m.expression == "1.5")
    }

    @Test("each operand can have its own separator")
    func separatorPerOperand() {
        let m = model()
        type(m, "1")
        m.tapSeparator()
        type(m, "5")
        m.tapOperator(.add)
        type(m, "2")
        m.tapSeparator()
        type(m, "5")
        #expect(m.expression == "1.5+2.5")
        #expect(m.result == Decimal(4))
    }

    // MARK: - Backspace / clear

    @Test("backspace removes the last character")
    func backspaceRemovesLast() {
        let m = model()
        type(m, "123")
        m.backspace()
        #expect(m.expression == "12")
    }

    @Test("backspace on empty is a no-op")
    func backspaceEmpty() {
        let m = model()
        m.backspace()
        #expect(m.expression == "")
    }

    @Test("clear resets everything")
    func clearResets() {
        let m = model()
        type(m, "12")
        m.tapOperator(.add)
        type(m, "3")
        m.clear()
        #expect(m.expression == "")
        #expect(m.result == nil)
        #expect(m.amountText == "")
    }

    // MARK: - Display result retention

    @Test("display result keeps the last valid value while the divisor is zero")
    func displayResultRetainedOnInvalid() {
        let m = model()
        type(m, "12")
        m.tapOperator(.divide) // "12/" → evaluates prefix to 12
        #expect(m.displayResult == Decimal(12))
        m.tapDigit("0")        // "12/0" → invalid, result nil
        #expect(m.result == nil)
        #expect(m.displayResult == Decimal(12)) // retained
    }

    // MARK: - amountText

    @Test("amountText is empty when there is no valid result")
    func amountTextEmptyWhenInvalid() {
        let m = model()
        #expect(m.amountText == "")
    }

    @Test("amountText reflects a fractional result")
    func amountTextFractional() {
        let m = model()
        type(m, "1000")
        m.tapOperator(.divide)
        type(m, "3")
        #expect(m.amountText == "333.33")
    }
}
