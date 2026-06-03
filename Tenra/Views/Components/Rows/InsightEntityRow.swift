//
//  InsightEntityRow.swift
//  Tenra
//
//  Shared "icon + name + subtitle + trailing amount" row for Insights detail
//  lists. Replaces three near-identical ad-hoc builders in InsightDetailView
//  (recurring payments, wealth accounts, dormant accounts). Built on UniversalRow.
//

import SwiftUI

/// Generic entity row: leading icon, a title with an arbitrary subtitle view, and
/// a trailing amount with an optional caption (e.g. "в месяц").
///
/// Use the `subtitle: String` convenience for plain-text subtitles; use the
/// `@ViewBuilder` initializer for dynamic subtitles (e.g. a relative date).
struct InsightEntityRow<Subtitle: View>: View {
    let iconSource: IconSource?
    let title: String
    let amount: Double
    let currency: String
    var amountColor: Color = AppColors.textPrimary
    var amountCaption: String? = nil
    @ViewBuilder let subtitle: () -> Subtitle

    init(
        iconSource: IconSource?,
        title: String,
        amount: Double,
        currency: String,
        amountColor: Color = AppColors.textPrimary,
        amountCaption: String? = nil,
        @ViewBuilder subtitle: @escaping () -> Subtitle
    ) {
        self.iconSource = iconSource
        self.title = title
        self.amount = amount
        self.currency = currency
        self.amountColor = amountColor
        self.amountCaption = amountCaption
        self.subtitle = subtitle
    }

    var body: some View {
        UniversalRow(
            config: .info,
            leadingIcon: iconSource.map { .auto(source: $0, size: AppIconSize.xxl) }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                subtitle()
            }
        } trailing: {
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                FormattedAmountText(
                    amount: amount,
                    currency: currency,
                    fontSize: AppTypography.body,
                    fontWeight: .semibold,
                    color: amountColor
                )
                if let amountCaption {
                    Text(amountCaption)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Plain-text subtitle convenience

extension InsightEntityRow where Subtitle == Text {
    init(
        iconSource: IconSource?,
        title: String,
        subtitle: String,
        amount: Double,
        currency: String,
        amountColor: Color = AppColors.textPrimary,
        amountCaption: String? = nil
    ) {
        self.init(
            iconSource: iconSource,
            title: title,
            amount: amount,
            currency: currency,
            amountColor: amountColor,
            amountCaption: amountCaption
        ) {
            Text(subtitle)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview("Recurring / Accounts / Dormant") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            InsightEntityRow(
                iconSource: .brandService("netflix"),
                title: "Netflix",
                subtitle: "Ежемесячно",
                amount: 4_990,
                currency: "KZT",
                amountCaption: "в месяц"
            )
            InsightEntityRow(
                iconSource: .sfSymbol("creditcard.fill"),
                title: "Kaspi Gold",
                subtitle: "KZT",
                amount: 1_250_400,
                currency: "KZT"
            )
            InsightEntityRow(
                iconSource: .sfSymbol("banknote.fill"),
                title: "Старый счёт",
                amount: 12_300,
                currency: "KZT",
                amountColor: AppColors.textSecondary
            ) {
                Text(Date().addingTimeInterval(-86_400 * 90), style: .relative)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .screenPadding()
    }
}
