//
//  AmountInputView.swift
//  AIFinanceManager
//
//  Large centered amount input with currency selector.
//  Supports copy/paste via long-press context menu.
//

import SwiftUI

struct AmountInputView: View {
    @Binding var amount: String
    @Binding var selectedCurrency: String
    let errorMessage: String?
    let baseCurrency: String
    var onAmountChange: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var displayAmount: String = "0"
    @State private var currentFontSize: CGFloat = 56
    @State private var containerWidth: CGFloat = 0

    // MARK: - Currency Conversion

    private struct ConversionKey: Equatable {
        let amount: String
        let currency: String
    }

    @State private var convertedAmount: Double?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Amount display — tap to focus, long-press for copy/paste
            Button {
                isFocused = true
            } label: {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: AppSpacing.xs) {
                        Text(displayAmount)
                            .font(.custom(AppTypography.fontFamily, size: currentFontSize).weight(.bold))
                            .contentTransition(.numericText())
                            .foregroundStyle(errorMessage != nil ? AppColors.destructive : AppColors.textPrimary)
                            .animation(AppAnimation.adaptiveSpring, value: displayAmount)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)

                        if isFocused {
                            BlinkingCursor()
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    copyAmount()
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
            }

            // Converted amount in base currency
            convertedAmountView
                .animation(AppAnimation.gentleSpring, value: shouldShowConversion)

            // Hidden TextField captures keyboard input
            TextField("", text: $amount)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: amount) { _, newValue in
                    updateDisplayAmount(newValue)
                    onAmountChange?(newValue)
                }
                // Debounced currency conversion — auto-cancels when amount or currency changes
                .task(id: ConversionKey(amount: amount, currency: selectedCurrency)) {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await updateConvertedAmount()
                }

            // Currency selector (centred)
            CurrencySelectorView(selectedCurrency: $selectedCurrency)

            // Validation error
            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.destructive)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppSpacing.lg)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard containerWidth != newWidth else { return }
            containerWidth = newWidth
            updateFontSize(for: newWidth)
        }
        .onChange(of: displayAmount) { _, _ in
            if containerWidth > 0 {
                updateFontSize(for: containerWidth)
            }
        }
        .onAppear {
            updateDisplayAmount(amount)
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = true
            }
        }
        .task {
            await updateConvertedAmount()
        }
    }

    // MARK: - Converted Amount View

    @ViewBuilder
    private var convertedAmountView: some View {
        if shouldShowConversion {
            HStack(spacing: AppSpacing.xs) {
                Text(String(localized: "currency.conversion.approximate"))
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textSecondary)

                if let converted = convertedAmount {
                    Text(formatConvertedAmount(converted))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textSecondaryAccessible)

                    Text(Formatting.currencySymbol(for: baseCurrency))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textSecondaryAccessible)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Currency Conversion Logic

    private var shouldShowConversion: Bool {
        guard selectedCurrency != baseCurrency else { return false }
        guard let numericAmount = parseAmount(amount), numericAmount > 0 else { return false }
        return true
    }

    private func parseAmount(_ text: String) -> Double? {
        Double(AmountInputFormatting.cleanAmountString(text))
    }

    private func formatConvertedAmount(_ value: Double) -> String {
        AmountInputFormatting.displayFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    @MainActor
    private func updateConvertedAmount() async {
        guard selectedCurrency != baseCurrency else {
            convertedAmount = nil
            return
        }

        guard let numericAmount = parseAmount(amount), numericAmount > 0 else {
            convertedAmount = nil
            return
        }

        // Fast path: use cached rate
        if let syncConverted = CurrencyConverter.convertSync(
            amount: numericAmount,
            from: selectedCurrency,
            to: baseCurrency
        ) {
            convertedAmount = syncConverted
            return
        }

        // Slow path: fetch rate from network
        if let asyncConverted = await CurrencyConverter.convert(
            amount: numericAmount,
            from: selectedCurrency,
            to: baseCurrency
        ) {
            convertedAmount = asyncConverted
        }
    }

    // MARK: - Copy / Paste

    private func copyAmount() {
        UIPasteboard.general.string = amount.isEmpty ? "0" : amount
    }

    private func pasteAmount() {
        guard let clipboardText = UIPasteboard.general.string else { return }
        let cleaned = AmountInputFormatting.cleanAmountString(clipboardText)
        guard !cleaned.isEmpty, Double(cleaned) != nil else { return }
        amount = cleaned
    }

    // MARK: - Display Amount

    private func updateDisplayAmount(_ text: String) {
        displayAmount = AmountInputFormatting.displayAmount(for: text)
    }

    // MARK: - Font Sizing

    private func updateFontSize(for width: CGFloat) {
        let newSize = AmountInputFormatting.calculateFontSize(
            for: displayAmount,
            containerWidth: width,
            baseFontSize: 56
        )
        if abs(currentFontSize - newSize) > 0.5 {
            currentFontSize = newSize
        }
    }
}

// BlinkingCursor is defined in Views/Components/AnimatedInputComponents.swift

#Preview("Amount Input - Empty") {
    @Previewable @State var amount = ""
    @Previewable @State var currency = "KZT"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: nil,
        baseCurrency: "KZT"
    )
}

#Preview("Amount Input - With Value") {
    @Previewable @State var amount = "1234.56"
    @Previewable @State var currency = "USD"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: nil,
        baseCurrency: "KZT"
    )
}

#Preview("Amount Input - Error") {
    @Previewable @State var amount = "abc"
    @Previewable @State var currency = "EUR"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: "Введите корректную сумму",
        baseCurrency: "KZT"
    )
}
