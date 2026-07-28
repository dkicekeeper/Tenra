//
//  FormattedAmountText.swift
//  Tenra
//
//  Created on 2026-02-11
//  Universal reusable component for displaying formatted amounts with smart decimal handling
//

import SwiftUI

/// Универсальный компонент для отображения денежных сумм с умной обработкой дробной части
///
/// Логика отображения:
/// - Если сотые = 0 и showDecimalsWhenZero = false → не показывает дробную часть (1000 ₸)
/// - Если сотые > 0 → показывает с прозрачностью decimalOpacity (1000.50 ₸)
/// - Если showDecimalsWhenZero = true → всегда показывает (1000.00 ₸)
struct FormattedAmountText: View {
    let amount: Double
    let currency: String
    let prefix: String
    let fontSize: Font
    let fontWeight: Font.Weight
    let color: Color
    let showDecimalsWhenZero: Bool
    let decimalOpacity: Double

    /// Инициализатор с полным набором параметров
    init(
        amount: Double,
        currency: String,
        prefix: String = "",
        fontSize: Font = AppTypography.body,
        fontWeight: Font.Weight = .semibold,
        color: Color = .primary,
        showDecimalsWhenZero: Bool = AmountDisplayConfiguration.shared.showDecimalsWhenZero,
        decimalOpacity: Double = AmountDisplayConfiguration.shared.decimalOpacity
    ) {
        self.amount = amount
        self.currency = currency
        self.prefix = prefix
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.showDecimalsWhenZero = showDecimalsWhenZero
        self.decimalOpacity = decimalOpacity
    }

    private var formattedParts: (integer: String, decimal: String, symbol: String) {
        let symbol = Formatting.currencySymbol(for: currency)
        let numberFormatter = AmountDisplayConfiguration.formatter

        let formatted = numberFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)

        // Разделяем на целую и дробную части
        let components = formatted.split(separator: Character(AmountDisplayConfiguration.shared.decimalSeparator))
        let integerPart = String(components.first ?? "0")
        let decimalPart = components.count > 1 ? String(components[1]) : "00"

        return (integerPart, decimalPart, symbol)
    }

    private var shouldShowDecimal: Bool {
        // Если showDecimalsWhenZero = true, всегда показываем
        if showDecimalsWhenZero {
            return true
        }
        // Иначе показываем только если есть дробная часть
        return amount.truncatingRemainder(dividingBy: 1) != 0
    }

    /// Single concatenated `Text` (one layout unit) so `.minimumScaleFactor` / line
    /// limits scale the whole amount uniformly — rendering the integer, decimal and
    /// symbol as separate `Text`s let each run scale independently (only the integer
    /// shrank while the decimal & symbol stayed full size). The reduced decimal opacity
    /// is preserved by colouring that run separately.
    private var composedText: Text {
        let parts = formattedParts

        // Built by interpolating styled `Text` runs into one `Text`. `Text.+` does the same
        // thing but was deprecated in iOS 26; interpolating a `Text` value preserves that
        // run's own font/weight/foregroundStyle, so the decimal run keeps its reduced
        // opacity exactly as before. Still ONE Text — that is what makes
        // `.minimumScaleFactor` scale the whole amount uniformly (see comment above).
        let integerRun = Text(prefix + parts.integer)
            .font(fontSize).fontWeight(fontWeight).foregroundStyle(color)
        let decimalRun = Text(AmountDisplayConfiguration.shared.decimalSeparator + parts.decimal)
            .font(fontSize).fontWeight(fontWeight).foregroundStyle(color.opacity(decimalOpacity))
        let symbolRun = Text(" " + parts.symbol)
            .font(fontSize).fontWeight(fontWeight).foregroundStyle(color)

        if shouldShowDecimal {
            return Text("\(integerRun)\(decimalRun)\(symbolRun)")
        }
        return Text("\(integerRun)\(symbolRun)")
    }

    var body: some View {
        composedText
            .contentTransition(.numericText())
            .animation(AppAnimation.gentleSpring, value: amount)
    }
}

#Preview("Different amounts") {
    VStack(spacing: 20) {
        FormattedAmountText(amount: 1000.00, currency: "KZT", prefix: "+", color: .green)
        FormattedAmountText(amount: 1234.56, currency: "USD", prefix: "-", color: .primary)
        FormattedAmountText(amount: 500.50, currency: "EUR", prefix: "", color: .blue)
        FormattedAmountText(amount: 999.00, currency: "RUB", prefix: "", color: .orange)
    }
    .padding()
}

#Preview("With showDecimalsWhenZero = true") {
    VStack(spacing: 20) {
        FormattedAmountText(amount: 1000.00, currency: "KZT", showDecimalsWhenZero: true)
        FormattedAmountText(amount: 500.50, currency: "USD", showDecimalsWhenZero: true)
    }
    .padding()
}
