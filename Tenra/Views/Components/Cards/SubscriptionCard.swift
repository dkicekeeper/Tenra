//
//  SubscriptionCard.swift
//  Tenra
//
//  Reusable subscription card component
//

import SwiftUI

struct SubscriptionCard: View {
    let subscription: RecurringSeries
    let nextChargeDate: Date?
    var baseCurrency: String = ""

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            IconView(
                source: subscription.iconSource,
                size: AppIconSize.xxl
            )

            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(subscription.description)
                    .font(AppTypography.bodyEmphasis.weight(.semibold))

                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
                    currency: subscription.currency,
                    fontSize: AppTypography.body,
                    color: .secondary
                )

                if !baseCurrency.isEmpty, subscription.currency != baseCurrency {
                    ConvertedAmountView(
                        amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
                        fromCurrency: subscription.currency,
                        toCurrency: baseCurrency,
                        fontSize: AppTypography.caption,
                        color: .secondary.opacity(0.7)
                    )
                }

                if let nextChargeDate = nextChargeDate {
                    Text(String(format: String(localized: "subscriptions.nextChargeOn"), formatDate(nextChargeDate)))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Status indicator
            statusIndicator
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        if let entityStatus = subscription.entityStatus {
            StatusIndicatorBadge(status: entityStatus, font: AppTypography.h4)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatters.displayDateFormatter
        return formatter.string(from: date)
    }
}

#Preview {
    SubscriptionCard(
        subscription: RecurringSeries(
            id: "1",
            amount: Decimal(9.99),
            currency: "USD",
            category: "Entertainment",
            description: "Netflix",
            accountId: "1",
            frequency: .monthly,
            startDate: DateFormatters.dateFormatter.string(from: Date()),
            kind: .subscription,
            iconSource: .brandService("Netflix"),
            status: .active
        ),
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
