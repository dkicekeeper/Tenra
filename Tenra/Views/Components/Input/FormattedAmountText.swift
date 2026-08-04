//
//  FormattedAmountText.swift
//  Tenra
//
//  Created on 2026-02-11
//  Universal reusable component for displaying formatted amounts with smart decimal handling
//

import SwiftUI

/// How an amount behaves when its container is too narrow for the full number.
enum AmountDisplayPolicy {
    /// Always the full number. Truncation/scaling is the caller's problem — use where
    /// the exact figure IS the content (amount editors, calculator display).
    case full
    /// Full number when it fits, abbreviated ("1,2 млн ₸") when it doesn't. Default:
    /// nothing changes visually anywhere the amount already fitted.
    case adaptive
    /// Always abbreviated (tight chrome: chart labels, badges).
    case compact
}

/// Универсальный компонент для отображения денежных сумм с умной обработкой дробной части
///
/// Логика отображения:
/// - Если сотые = 0 и showDecimalsWhenZero = false → не показывает дробную часть (1000 ₸)
/// - Если сотые > 0 → показывает с прозрачностью decimalOpacity (1000.50 ₸)
/// - Если showDecimalsWhenZero = true → всегда показывает (1000.00 ₸)
///
/// Overflow: see `AmountDisplayPolicy`. VoiceOver always reads the FULL amount, whichever
/// variant is drawn — an abbreviation is a layout concession, not a change of value.
struct FormattedAmountText: View {
    let amount: Double
    let currency: String
    let prefix: String
    let fontSize: Font
    let fontWeight: Font.Weight
    let color: Color
    let showDecimalsWhenZero: Bool
    let decimalOpacity: Double
    let policy: AmountDisplayPolicy

    /// Инициализатор с полным набором параметров
    init(
        amount: Double,
        currency: String,
        prefix: String = "",
        fontSize: Font = AppTypography.body,
        fontWeight: Font.Weight = .semibold,
        color: Color = .primary,
        showDecimalsWhenZero: Bool = AmountDisplayConfiguration.shared.showDecimalsWhenZero,
        decimalOpacity: Double = AmountDisplayConfiguration.shared.decimalOpacity,
        policy: AmountDisplayPolicy = .adaptive
    ) {
        self.amount = amount
        self.currency = currency
        self.prefix = prefix
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.showDecimalsWhenZero = showDecimalsWhenZero
        self.decimalOpacity = decimalOpacity
        self.policy = policy
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

    // MARK: - Compact variants

    /// Abbreviated string for `digits` fraction digits, as one styled `Text`.
    /// No dimmed decimal run here: in "1,2 млн" the digit after the separator is a
    /// significant figure, not a cents tail.
    private func compactText(digits: Int) -> Text {
        Text(prefix + Formatting.formatCurrencyCompact(amount, currency: currency, maxFractionDigits: digits))
            .font(fontSize).fontWeight(fontWeight).foregroundStyle(color)
    }

    /// Fallback candidate for `ViewThatFits`, or the full text when abbreviating wouldn't
    /// actually help.
    ///
    /// Compact unit names are localized words, so "10 тыс. ₸" is LONGER than "10 000 ₸";
    /// swapping in a longer string would overflow harder, not less. Falling back to the
    /// full text keeps every `ViewThatFits` slot filled — an `if` here would leave an
    /// `EmptyView` candidate, which always "fits" and would render nothing at all.
    private func candidate(digits: Int) -> Text {
        let parts = formattedParts
        let fullLength = (prefix + parts.integer + parts.symbol).count
        let compact = prefix + Formatting.formatCurrencyCompact(amount, currency: currency, maxFractionDigits: digits)
        guard compact.count < fullLength else { return composedText }
        return compactText(digits: digits)
    }

    /// Full amount, always — VoiceOver must not lose precision to a layout decision.
    private var accessibilityText: String {
        prefix + Formatting.formatCurrencySmart(amount, currency: currency, showDecimalsWhenZero: showDecimalsWhenZero)
    }

    var body: some View {
        Group {
            switch policy {
            case .full:
                composedText
            case .compact:
                compactText(digits: 1)
            case .adaptive:
                // First candidate that fits wins, so an amount with room to spare renders
                // exactly as it did before this policy existed.
                ViewThatFits(in: .horizontal) {
                    composedText.lineLimit(1)
                    candidate(digits: 1).lineLimit(1)
                    candidate(digits: 0).lineLimit(1)
                }
            }
        }
        .contentTransition(.numericText())
        .animation(AppAnimation.gentleSpring, value: amount)
        .accessibilityLabel(accessibilityText)
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

#Preview("Adaptive — narrowing container") {
    // Same amount, shrinking width: full → "1,2 млн ₸" → "1 млн ₸".
    VStack(alignment: .leading, spacing: 16) {
        ForEach([260.0, 150.0, 110.0, 80.0], id: \.self) { width in
            HStack {
                Text("Баланс")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                FormattedAmountText(amount: 148_920_450, currency: "KZT")
            }
            .frame(width: width)
            .padding(8)
            .background(AppColors.bgCard)
        }
        HStack {
            Text("full policy")
                .font(AppTypography.bodySmall)
            Spacer()
            FormattedAmountText(amount: 148_920_450, currency: "KZT", policy: .full)
        }
        .frame(width: 110)
        .padding(8)
        .background(AppColors.bgCard)
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
