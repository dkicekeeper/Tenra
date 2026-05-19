//
//  InfoRow.swift
//  Tenra
//
//  Reusable info row component (label: value)
//  Migrated to UniversalRow architecture - 2026-02-16
//

import SwiftUI

/// Info row component for displaying label + value pairs
/// Now built on top of UniversalRow for consistency
struct InfoRow: View {
    let icon: String?
    let label: String
    let value: String
    let amountDisplay: InfoRowAmount?

    init(icon: String? = nil, label: String, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
        self.amountDisplay = nil
    }

    /// Money variant: trailing renders via FormattedAmountText (smart decimal hiding +
    /// dimmed `.XX`). `value` is computed via `formatCurrencySmart` as accessibility fallback.
    init(
        icon: String? = nil,
        label: String,
        amount: Double,
        currency: String,
        prefix: String = ""
    ) {
        self.icon = icon
        self.label = label
        self.value = prefix + Formatting.formatCurrencySmart(amount, currency: currency)
        self.amountDisplay = InfoRowAmount(amount: amount, currency: currency, prefix: prefix)
    }

    var body: some View {
        UniversalRow(
            config: .info,
            leadingIcon: icon.map { .sfSymbol($0, color: AppColors.accent, size: AppIconSize.lg) }
        ) {
            HStack {
                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if let display = amountDisplay {
                    FormattedAmountText(
                        amount: display.amount,
                        currency: display.currency,
                        prefix: display.prefix,
                        fontSize: AppTypography.bodyEmphasis,
                        fontWeight: .semibold,
                        color: AppColors.textPrimary
                    )
                } else {
                    Text(value)
                        .font(AppTypography.bodyEmphasis)
                }
            }
        } trailing: {
            EmptyView()
        }
    }
}

#Preview {
    VStack() {
        InfoRow(icon: "tag.fill", label: "Категория", value: "Food")
        InfoRow(icon: "calendar", label: "Частота", value: "Ежемесячно")
        InfoRow(icon: "clock.fill", label: "Следующее списание", value: "15 января 2026")
        InfoRow(label: "Без иконки", value: "Значение")
    }
    .padding()
}
