//
//  ExpressionEvaluatorTests.swift
//  TenraTests
//
//  Pins the pure arithmetic evaluator behind the calculator amount input.
//

import Testing
import Foundation
@testable import Tenra

@Suite("ExpressionEvaluator")
struct ExpressionEvaluatorTests {

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: - Plain numbers

    @Test("a bare integer evaluates to itself")
    func bareInteger() {
        #expect(ExpressionEvaluator.evaluate("1200") == dec("1200"))
    }

    @Test("a bare decimal evaluates to itself")
    func bareDecimal() {
        #expect(ExpressionEvaluator.evaluate("12.5") == dec("12.5"))
    }

    // MARK: - Basic operators

    @Test("addition")
    func addition() {
        #expect(ExpressionEvaluator.evaluate("1200+350") == dec("1550"))
    }

    @Test("subtraction can go negative")
    func subtractionNegative() {
        #expect(ExpressionEvaluator.evaluate("2-3") == dec("-1"))
    }

    @Test("multiplication")
    func multiplication() {
        #expect(ExpressionEvaluator.evaluate("12*3") == dec("36"))
    }

    @Test("division")
    func division() {
        #expect(ExpressionEvaluator.evaluate("100/4") == dec("25"))
    }

    // MARK: - Precedence

    @Test("multiplication binds tighter than addition")
    func precedenceMulOverAdd() {
        #expect(ExpressionEvaluator.evaluate("100+10*2") == dec("120"))
    }

    @Test("division binds tighter than subtraction")
    func precedenceDivOverSub() {
        #expect(ExpressionEvaluator.evaluate("10-2*3") == dec("4"))
        #expect(ExpressionEvaluator.evaluate("100/4+1") == dec("26"))
    }

    @Test("left-associative same-precedence chain")
    func leftAssociative() {
        #expect(ExpressionEvaluator.evaluate("10-3-2") == dec("5"))
        #expect(ExpressionEvaluator.evaluate("100/5/2") == dec("10"))
    }

    // MARK: - Rounding (money, 2dp)

    @Test("long quotient rounds to 2 decimals")
    func longQuotientRounds() {
        #expect(ExpressionEvaluator.evaluate("1000/3") == dec("333.33"))
        #expect(ExpressionEvaluator.evaluate("2/3") == dec("0.67"))
    }

    // MARK: - Display glyphs & separators

    @Test("accepts display glyphs × ÷ −")
    func acceptsDisplayGlyphs() {
        #expect(ExpressionEvaluator.evaluate("100+10×2") == dec("120"))
        #expect(ExpressionEvaluator.evaluate("100÷4") == dec("25"))
        #expect(ExpressionEvaluator.evaluate("5−2") == dec("3"))
    }

    @Test("accepts comma as decimal separator")
    func acceptsCommaSeparator() {
        #expect(ExpressionEvaluator.evaluate("12,5+0,5") == dec("13"))
    }

    // MARK: - Edge cases

    @Test("trailing operator is dropped and the prefix is evaluated")
    func trailingOperator() {
        #expect(ExpressionEvaluator.evaluate("1200+") == dec("1200"))
        #expect(ExpressionEvaluator.evaluate("1200+350*") == dec("1550"))
    }

    @Test("division by zero returns nil")
    func divisionByZero() {
        #expect(ExpressionEvaluator.evaluate("5/0") == nil)
    }

    @Test("empty input returns nil")
    func emptyInput() {
        #expect(ExpressionEvaluator.evaluate("") == nil)
        #expect(ExpressionEvaluator.evaluate("   ") == nil)
    }

    @Test("garbage / leading operator returns nil")
    func garbage() {
        #expect(ExpressionEvaluator.evaluate("+5") == nil)
        #expect(ExpressionEvaluator.evaluate("abc") == nil)
    }
}
