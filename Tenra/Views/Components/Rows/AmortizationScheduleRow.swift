//
//  AmortizationScheduleRow.swift
//  Tenra
//
//  Reusable row for a single loan amortization-schedule entry: payment number
//  + date on the left, payment amount (and interest portion, if any) on the
//  right, and a paid/upcoming indicator. Unpaid rows are dimmed.
//

import SwiftUI

struct AmortizationScheduleRow: View {
    let entry: LoanPaymentService.AmortizationEntry
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: entry.isPaid ? "checkmark.circle.fill" : "circle")
                .font(.system(size: AppIconSize.lg))
                .foregroundStyle(entry.isPaid ? AppColors.income : AppColors.textSecondary)
            
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("#\(entry.paymentNumber)")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Text(DateFormatters.displayString(from: entry.date))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: entry.payment).doubleValue,
                    currency: currency,
                    fontSize: AppTypography.bodyEmphasis
                )
                if entry.interest > 0 {
                    Text(String(
                        format: String(localized: "loan.interestShort", defaultValue: "int: %@"),
                        Formatting.formatCurrencySmart(
                            NSDecimalNumber(decimal: entry.interest).doubleValue,
                            currency: currency
                        )
                    ))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.expense)
                }
            }
        }
        .futureTransactionStyle(isFuture: !entry.isPaid)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Amortization Rows") {
    VStack(spacing: AppSpacing.md) {
        AmortizationScheduleRow(
            entry: LoanPaymentService.AmortizationEntry(
                id: 1,
                paymentNumber: 1,
                date: "2025-01-05",
                payment: 34_832,
                principal: 34_832,
                interest: 0,
                remainingBalance: 801_151,
                isPaid: true
            ),
            currency: "KZT"
        )
        AmortizationScheduleRow(
            entry: LoanPaymentService.AmortizationEntry(
                id: 7,
                paymentNumber: 7,
                date: "2025-07-05",
                payment: 41_200,
                principal: 33_700,
                interest: 7_500,
                remainingBalance: 540_000,
                isPaid: false
            ),
            currency: "KZT"
        )
    }
    .padding(AppSpacing.lg)
}
