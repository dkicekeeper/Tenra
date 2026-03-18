//
//  AnimatedInputComponents.swift
//  AIFinanceManager
//
//  Created: Phase 16 - AnimatedHeroInput
//
//  Shared building blocks for animated text/amount input:
//  - BlinkingCursor: blinking insertion point indicator
//  - AmountDigitDisplay: animated amount display with .numericText() transition
//  - AmountInput: self-contained amount input (display + hidden TextField + focus)
//

import SwiftUI

// MARK: - BlinkingCursor

/// Animated blinking cursor shown when input is focused.
struct BlinkingCursor: View {
    var height: CGFloat = AppSize.cursorHeight

    @State private var opacity: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(AppColors.textPrimary)
            .frame(width: AppSize.cursorWidth, height: height)
            .opacity(opacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    opacity = 0.0
                }
            }
            .onDisappear {
                opacity = 1.0
            }
    }
}

// MARK: - AmountDigitDisplay

/// Animated amount display using a single `Text` with `.numericText()` transition.
///
/// Font sizing handled by `.minimumScaleFactor(0.3)` — no manual `@State` font size,
/// no measurement mismatch, no animation conflicts. SwiftUI handles sizing internally
/// as part of Text rendering in the same render pass as the content transition.
///
/// Visual grouping via `AttributedString.kern` — NOT space characters.
/// `.numericText()` does positional character diffing. Spaces in the string shift
/// positions on grouping change ("1 234" → "12 345"), causing multiple digits to animate.
/// Kern is a styling attribute, invisible to `.numericText()` — the string stays "12345"
/// but renders as "12 345". Only the actual typed/deleted digit animates.
struct AmountDigitDisplay: View {
    let rawAmount: String
    var baseFontSize: CGFloat = 56
    var color: Color = AppColors.textPrimary
    var isFocused: Bool = false
    var cursorHeight: CGFloat = AppSize.cursorHeight

    /// Clean digit string — no space characters, stable positions for `.numericText()`.
    private var displayAmount: String {
        let cleaned = AmountInputFormatting.cleanAmountString(rawAmount)
        if cleaned.isEmpty { return "0" }
        guard let decimal = Decimal(string: cleaned), decimal != 0 else { return "0" }
        return cleaned
    }

    /// Attributed string with kern at group boundaries for visual digit grouping.
    /// Kern scales with `.minimumScaleFactor` since it's part of the text render pass.
    private var attributedDisplay: AttributedString {
        let raw = displayAmount
        var result = AttributedString(raw)

        // Find integer part length (before decimal point)
        let integerEnd = raw.firstIndex(of: ".") ?? raw.endIndex
        let integerCount = raw.distance(from: raw.startIndex, to: integerEnd)

        guard integerCount > 3 else { return result }

        let groupKern = baseFontSize * 0.25

        // Add kern after characters that precede a group boundary.
        // For "1234567" (count=7): kern after index 0 and 3 → "1 234 567"
        var attrIndex = result.startIndex
        for charIndex in 0..<integerCount {
            let nextIndex = result.index(afterCharacter: attrIndex)
            if charIndex < integerCount - 1 && (integerCount - charIndex - 1) % 3 == 0 {
                result[attrIndex..<nextIndex].kern = groupKern
            }
            attrIndex = nextIndex
        }

        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: AppSpacing.xs) {
                Text(attributedDisplay)
                    .font(.custom(AppTypography.fontFamily, size: baseFontSize).weight(.bold))
                    .contentTransition(.numericText())
                    .foregroundStyle(color)
                    .animation(AppAnimation.contentSpring, value: displayAmount)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)

                BlinkingCursor(height: cursorHeight)
                    .opacity(isFocused ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - AmountInput

/// Self-contained amount input: animated display + hidden TextField + focus management.
///
/// Replaces both `AmountInputView`'s core and the old `AnimatedAmountInput`.
/// `AmountInputView` wraps this with currency selector, conversion display, and error.
/// `EditableHeroSection` uses this directly.
///
/// Usage:
/// ```swift
/// // Transaction form (auto-focus, copy/paste)
/// AmountInput(amount: $amount, autoFocus: true, showContextMenu: true)
///
/// // Hero section (custom size, placeholder color)
/// AmountInput(amount: $balance, baseFontSize: 48, placeholderColor: AppColors.textTertiary)
/// ```
struct AmountInput: View {
    @Binding var amount: String
    var baseFontSize: CGFloat = 56
    var color: Color = AppColors.textPrimary
    /// Color when amount is empty/zero. When nil, uses `color`.
    var placeholderColor: Color? = nil
    var cursorHeight: CGFloat = AppSize.cursorHeight
    var autoFocus: Bool = false
    var showContextMenu: Bool = false
    var onAmountChange: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool

    private var isPlaceholder: Bool {
        amount.isEmpty || amount == "0"
    }

    private var effectiveColor: Color {
        if let placeholderColor, isPlaceholder { return placeholderColor }
        return color
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                HapticManager.light()
                isFocused = true
            } label: {
                AmountDigitDisplay(
                    rawAmount: amount,
                    baseFontSize: baseFontSize,
                    color: effectiveColor,
                    isFocused: isFocused,
                    cursorHeight: cursorHeight
                )
            }
            .buttonStyle(.plain)
            .contextMenu(showContextMenu ? ContextMenu {
                Button {
                    UIPasteboard.general.string = amount.isEmpty ? "0" : amount
                } label: {
                    Label(String(localized: "button.copy"), systemImage: "doc.on.doc")
                }

                if UIPasteboard.general.hasStrings {
                    Button {
                        pasteAmount()
                    } label: {
                        Label(String(localized: "button.paste"), systemImage: "doc.on.clipboard")
                    }
                }
            } : nil)

            // Hidden TextField — actual input source
            TextField("", text: $amount)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: amount) { _, newValue in
                    onAmountChange?(newValue)
                }
        }
        .task {
            guard autoFocus else { return }
            await Task.yield()
            isFocused = true
        }
    }

    private func pasteAmount() {
        guard let clipboardText = UIPasteboard.general.string else { return }
        let cleaned = AmountInputFormatting.cleanAmountString(clipboardText)
        guard !cleaned.isEmpty, Double(cleaned) != nil else { return }
        amount = cleaned
    }
}
