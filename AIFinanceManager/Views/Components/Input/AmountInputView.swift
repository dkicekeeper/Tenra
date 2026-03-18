//
//  AmountInputView.swift
//  AIFinanceManager
//
//  Large centered amount input with currency selector and conversion display.
//  Core input mechanics delegated to AmountInput (AnimatedInputComponents.swift).
//

import SwiftUI

struct AmountInputView: View {
    @Binding var amount: String
    @Binding var selectedCurrency: String
    let errorMessage: String?
    let baseCurrency: String
    var onAmountChange: ((String) -> Void)? = nil

    // MARK: - Currency Conversion

    @State private var convertedAmount: Double?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            AmountInput(
                amount: $amount,
                baseFontSize: 56,
                color: errorMessage != nil ? AppColors.destructive : AppColors.textPrimary,
                autoFocus: true,
                showContextMenu: true,
                onAmountChange: onAmountChange
            )

            // Converted amount in base currency
            convertedAmountView
                .animation(AppAnimation.gentleSpring, value: shouldShowConversion)

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
//        .padding(AppSpacing.lg)
        // Debounced conversion for amount typing
        .task(id: amount) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await updateConvertedAmount()
        }
        // Immediate conversion on currency change
        .onChange(of: selectedCurrency) { _, _ in
            Task { await updateConvertedAmount() }
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
                        .contentTransition(.numericText())
                        .animation(AppAnimation.gentleSpring, value: converted)

                    Text(Formatting.currencySymbol(for: baseCurrency))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textSecondaryAccessible)
                        .contentTransition(.numericText())
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

    /// Formats converted amount as AttributedString with kern-based grouping.
    /// Same approach as AmountDigitDisplay — no space characters, so `.numericText()`
    /// only animates the actual changed digits.
    private func formatConvertedAmount(_ value: Double) -> AttributedString {
        // Format without grouping — raw digits for stable .numericText() positions
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."

        let raw = formatter.string(from: NSNumber(value: value)) ?? "0"
        var result = AttributedString(raw)

        let integerEnd = raw.firstIndex(of: ".") ?? raw.endIndex
        let integerCount = raw.distance(from: raw.startIndex, to: integerEnd)

        guard integerCount > 3 else { return result }

        let groupKern: CGFloat = 3.0

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
}

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
