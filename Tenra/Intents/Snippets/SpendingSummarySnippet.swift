//
//  SpendingSummarySnippet.swift
//  Tenra
//

import SwiftUI

struct SpendingSummarySnippet: View {

    let total: SpendingTotal
    let period: SpendingPeriodAppEnum

    private var periodLabel: String {
        switch period {
        case .today: String(localized: "intent.checkSpending.period.today")
        case .thisWeek: String(localized: "intent.checkSpending.period.week")
        case .thisMonth: String(localized: "intent.checkSpending.period.month")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(periodLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FormattedAmountText(
                amount: total.amount,
                currency: total.currency,
                fontSize: .largeTitle,
                fontWeight: .semibold
            )

            Text(String(
                format: String(localized: "intent.checkSpending.transactionCount"),
                total.transactionCount
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.lg)
    }
}
