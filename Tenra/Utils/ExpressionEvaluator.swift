//
//  ExpressionEvaluator.swift
//  Tenra
//
//  Pure arithmetic evaluator for the calculator amount input. Operates on `Decimal`
//  (not NSExpression) to preserve money precision. No UI, no app state.
//

import Foundation

nonisolated enum ExpressionEvaluator {

    /// Evaluates a flat arithmetic expression (`+ - * /`, standard precedence) and returns
    /// the result rounded to 2 decimal places. Returns `nil` for empty / malformed input or
    /// division by zero. A trailing operator is dropped and the valid prefix is evaluated
    /// (`"1200+"` → `1200`).
    ///
    /// Accepts both canonical ASCII operators (`* / -`) and the display glyphs (`× ÷ −`),
    /// and both `.` and `,` as the decimal separator.
    static func evaluate(_ expression: String) -> Decimal? {
        let normalized = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "\u{2212}", with: "-") // minus sign → hyphen-minus
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")

        guard !normalized.isEmpty else { return nil }
        guard var tokens = tokenize(normalized) else { return nil }

        // Drop a trailing operator and evaluate the valid prefix ("1200+" → "1200").
        while case .op = tokens.last {
            tokens.removeLast()
        }
        guard !tokens.isEmpty else { return nil }

        guard let rpn = toRPN(tokens), let result = evalRPN(rpn) else { return nil }
        return rounded(result)
    }

    // MARK: - Tokenizing

    private enum Token: Equatable {
        case number(Decimal)
        case op(Character)
    }

    private static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        var numberBuffer = ""

        func flushNumber() -> Bool {
            guard !numberBuffer.isEmpty else { return true }
            guard let value = Decimal(string: numberBuffer) else { return false }
            tokens.append(.number(value))
            numberBuffer = ""
            return true
        }

        for ch in s {
            if ch.isNumber || ch == "." {
                numberBuffer.append(ch)
            } else if "+-*/".contains(ch) {
                guard flushNumber() else { return nil }
                tokens.append(.op(ch))
            } else {
                return nil // invalid character
            }
        }
        guard flushNumber() else { return nil }
        return tokens
    }

    // MARK: - Shunting-yard → RPN

    private static func precedence(_ op: Character) -> Int {
        (op == "*" || op == "/") ? 2 : 1
    }

    private static func toRPN(_ tokens: [Token]) -> [Token]? {
        // Structural check: must be number (op number)* — reject leading/trailing/double ops.
        var expectNumber = true
        for token in tokens {
            switch token {
            case .number: guard expectNumber else { return nil }; expectNumber = false
            case .op:     guard !expectNumber else { return nil }; expectNumber = true
            }
        }
        guard !expectNumber else { return nil } // ended on an operator

        var output: [Token] = []
        var operators: [Character] = []
        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .op(let op):
                while let top = operators.last, precedence(top) >= precedence(op) {
                    output.append(.op(operators.removeLast()))
                }
                operators.append(op)
            }
        }
        while let op = operators.popLast() {
            output.append(.op(op))
        }
        return output
    }

    private static func evalRPN(_ rpn: [Token]) -> Decimal? {
        var stack: [Decimal] = []
        for token in rpn {
            switch token {
            case .number(let value):
                stack.append(value)
            case .op(let op):
                guard stack.count >= 2 else { return nil }
                let rhs = stack.removeLast()
                let lhs = stack.removeLast()
                switch op {
                case "+": stack.append(lhs + rhs)
                case "-": stack.append(lhs - rhs)
                case "*": stack.append(lhs * rhs)
                case "/":
                    guard rhs != 0 else { return nil }
                    stack.append(lhs / rhs)
                default: return nil
                }
            }
        }
        return stack.count == 1 ? stack.first : nil
    }

    // MARK: - Rounding (money, 2dp, half away from zero)

    private static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
