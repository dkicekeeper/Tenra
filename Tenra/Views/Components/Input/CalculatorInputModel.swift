//
//  CalculatorInputModel.swift
//  Tenra
//
//  View-agnostic state machine for the calculator amount keypad. Holds the raw
//  expression (canonical ASCII operators `+ - * /`, `.` separator), derives the
//  evaluated result via ExpressionEvaluator, and exposes the amount string the form
//  binds to. No UIKit, no view code — fully unit-testable.
//

import Foundation

@MainActor
@Observable
final class CalculatorInputModel {

    enum Op: Character, CaseIterable {
        case add = "+", subtract = "-", multiply = "*", divide = "/"
    }

    /// Raw canonical expression, e.g. "1200+350".
    private(set) var expression: String = ""

    /// Retained so the large display never blanks while the expression is briefly invalid
    /// (e.g. a "0" divisor mid-typing).
    private var lastValidResult: Decimal?

    private static let operatorChars = "+-*/"

    // MARK: - Intents

    func tapDigit(_ digit: Character) {
        // Replace a lone leading zero in the current operand: "0" + "5" → "5".
        if currentOperand == "0" {
            expression.removeLast()
        }
        expression.append(digit)
        refresh()
    }

    func tapOperator(_ op: Op) {
        guard !expression.isEmpty else { return } // no leading operator
        if let last = expression.last {
            if Self.operatorChars.contains(last) {
                expression.removeLast() // replace the pending operator
            } else if last == "." {
                expression.removeLast() // drop a dangling separator before the operator
            }
        }
        expression.append(op.rawValue)
        refresh()
    }

    func tapSeparator() {
        let operand = currentOperand
        guard !operand.contains(".") else { return } // one separator per operand
        expression.append(operand.isEmpty ? "0." : ".")
        refresh()
    }

    func backspace() {
        guard !expression.isEmpty else { return }
        expression.removeLast()
        refresh()
    }

    func clear() {
        expression = ""
        lastValidResult = nil
    }

    // MARK: - Derived state

    /// Evaluated result of the current expression, or `nil` if incomplete/invalid.
    var result: Decimal? { ExpressionEvaluator.evaluate(expression) }

    /// `true` once the expression contains an operator (drives the secondary line).
    var hasOperator: Bool { expression.contains { Self.operatorChars.contains($0) } }

    /// Value to show large: the live result, falling back to the last valid result so the
    /// display never blanks mid-typing (e.g. while a divisor is "0").
    var displayResult: Decimal? { result ?? lastValidResult }

    /// Plain amount string the form binds to ("" when there is no valid result).
    var amountText: String {
        guard let result else { return "" }
        return AmountInputFormatting.bindingString(for: result)
    }

    // MARK: - Helpers

    /// The operand currently being typed — everything after the last operator.
    private var currentOperand: String {
        if let idx = expression.lastIndex(where: { Self.operatorChars.contains($0) }) {
            return String(expression[expression.index(after: idx)...])
        }
        return expression
    }

    private func refresh() {
        if let result { lastValidResult = result }
    }
}
