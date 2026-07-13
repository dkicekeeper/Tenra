//
//  CalculatorKeypad.swift
//  Tenra
//
//  In-app calculator keypad driving a CalculatorInputModel. Replaces the system
//  keyboard for amount entry, so there is no keyboard-raise animation — the input is
//  present the instant the screen appears.
//
//  Layout (4×4):
//      1 2 3 +
//      4 5 6 −
//      7 8 9 ×
//      , 0 ⌫ ÷
//  Tap ⌫ to delete; long-press ⌫ to clear the whole expression.
//

import SwiftUI

struct CalculatorKeypad: View {
    let model: CalculatorInputModel

    /// Press state for the backspace key. The digit/operator keys get their press
    /// feedback from `.buttonStyle(.bounce)`; backspace can't be a plain Button
    /// because it also needs a long-press (clear), so it drives its own scale via
    /// the long-press gesture's `onPressingChanged`.
    @State private var backspacePressed = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: AppSpacing.sm),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
            digit("1"); digit("2"); digit("3"); op(.add, "+")
            digit("4"); digit("5"); digit("6"); op(.subtract, "−")
            digit("7"); digit("8"); digit("9"); op(.multiply, "×")
            separatorKey(); digit("0"); backspaceKey(); op(.divide, "÷")
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        // The keypad's presence in the tree is the single source of truth for "amount
        // entry is active". Hosts mount it conditionally (e.g. `if !descriptionFocused`);
        // the amount display's cursor reads `model.isActive`, so it follows automatically
        // whatever condition — current or future — governs the keypad's visibility.
        .onAppear { model.isActive = true }
        .onDisappear { model.isActive = false }
    }

    // MARK: - Keys

    private func digit(_ value: String) -> some View {
        keyButton(background: AppColors.bgCard) {
            model.tapDigit(Character(value))
        } label: {
            Text(value).foregroundStyle(AppColors.textPrimary)
        }
    }

    private func op(_ op: CalculatorInputModel.Op, _ glyph: String) -> some View {
        keyButton(background: AppColors.accent.opacity(0.12)) {
            model.tapOperator(op)
        } label: {
            Text(glyph).foregroundStyle(AppColors.accent)
        }
        .accessibilityLabel(accessibilityLabel(for: op))
    }

    private func separatorKey() -> some View {
        keyButton(background: AppColors.bgCard) {
            model.tapSeparator()
        } label: {
            Text(",").foregroundStyle(AppColors.textPrimary)
        }
        .accessibilityLabel(Text(String(localized: "calculator.separator", defaultValue: "Decimal separator")))
    }

    private func backspaceKey() -> some View {
        keyShape(background: AppColors.bgCard) {
            Image(systemName: "delete.left").foregroundStyle(AppColors.textSecondary)
        }
        .scaleEffect(backspacePressed ? 0.96 : 1.0)
        .brightness(backspacePressed ? -0.05 : 0.0)
        .animation(AppAnimation.adaptiveSpring, value: backspacePressed)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .onTapGesture {
            HapticManager.light()
            model.backspace()
        }
        .onLongPressGesture(
            minimumDuration: 0.35,
            perform: {
                HapticManager.medium()
                model.clear()
            },
            onPressingChanged: { pressing in
                backspacePressed = pressing
            }
        )
        .accessibilityLabel(Text(String(localized: "calculator.backspace", defaultValue: "Delete")))
        .accessibilityHint(Text(String(localized: "calculator.clearHint", defaultValue: "Press and hold to clear")))
    }

    // MARK: - Builders

    private func keyButton(
        background: Color,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            keyShape(background: background, content: label)
        }
        .buttonStyle(.bounce)
    }

    private func keyShape(
        background: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .font(.custom(AppTypography.fontFamily, size: 24).weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    private func accessibilityLabel(for op: CalculatorInputModel.Op) -> Text {
        switch op {
        case .add:      return Text(String(localized: "calculator.add", defaultValue: "Plus"))
        case .subtract: return Text(String(localized: "calculator.subtract", defaultValue: "Minus"))
        case .multiply: return Text(String(localized: "calculator.multiply", defaultValue: "Multiply"))
        case .divide:   return Text(String(localized: "calculator.divide", defaultValue: "Divide"))
        }
    }
}
