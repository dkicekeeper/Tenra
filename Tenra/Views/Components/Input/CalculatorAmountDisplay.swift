//
//  CalculatorAmountDisplay.swift
//  Tenra
//
//  Large live result + small expression line for the calculator amount input.
//  Reads a CalculatorInputModel; the keypad (CalculatorKeypad) mutates it.
//

import SwiftUI

struct CalculatorAmountDisplay: View {
    let model: CalculatorInputModel
    var baseFontSize: CGFloat = 56

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            // Secondary line — the raw expression, only once an operator is present.
            if model.hasOperator {
                Text(displayExpression)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .transition(.opacity)
            }

            // Primary line — raw number while typing a single operand, else the live result.
            AmountDigitDisplay(
                rawAmount: primaryRaw,
                baseFontSize: baseFontSize,
                isFocused: true
            )
        }
        .animation(AppAnimation.fastAnimation, value: model.hasOperator)
    }

    /// What the large display shows: the raw operand while no operator is present (so
    /// in-progress typing like "12," is preserved), otherwise the evaluated result.
    private var primaryRaw: String {
        guard model.hasOperator else { return model.expression }
        if let result = model.displayResult {
            return AmountInputFormatting.bindingString(for: result)
        }
        return "0"
    }

    /// Canonical expression rendered with display glyphs (× ÷ −) and the comma separator.
    private var displayExpression: String {
        var out = ""
        for ch in model.expression {
            switch ch {
            case "+": out += " + "
            case "-": out += " − "
            case "*": out += " × "
            case "/": out += " ÷ "
            case ".": out += ","
            default:  out.append(ch)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
