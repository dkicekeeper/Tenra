//
//  LoanCard.swift
//  Tenra
//
//  Card displaying loan summary: icon, name, bank, type badge,
//  progress bar, next payment date, and remaining count.
//

import SwiftUI

struct LoanCard: View {
    let loan: Account

    var body: some View {
        if let loanInfo = loan.loanInfo {
            let isPaidOff = loanInfo.isPaidOff
            let progress = isPaidOff ? 1.0 : LoanPaymentService.progressPercentage(loanInfo: loanInfo)
            let nextDate = isPaidOff ? nil : LoanPaymentService.nextPaymentDate(loanInfo: loanInfo)
            let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Header: icon + name + bank + type badge
                HStack(alignment: .top) {
                    IconView(source: loan.iconSource, size: AppIconSize.xxl)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loan.name)
                            .font(AppTypography.h4)
                        Text(loanInfo.bankName)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    LoanTypeBadge(loanType: loanInfo.loanType, isPaidOff: isPaidOff)
                }

                // Progress
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        FormattedAmountText(
                            amount: NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue,
                            currency: loan.currency,
                            fontSize: AppTypography.body,
                            fontWeight: .regular,
                            color: AppColors.textSecondary
                        )
                        Spacer()
                        FormattedAmountText(
                            amount: NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue,
                            currency: loan.currency,
                            fontSize: AppTypography.body,
                            fontWeight: .regular,
                            color: AppColors.textSecondary
                        )
                    }
                    ProgressView(value: progress)
                        .tint(AppColors.income)
                        .accessibilityValue(String(format: "%.0f%%", progress * 100))
                }

                // Footer: next payment + remaining. A closed loan has neither — it shows
                // when it was paid off instead.
                HStack {
                    if isPaidOff {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.income)
                            Text(closedFooterText(loanInfo: loanInfo))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                    } else {
                        if let nextDate = nextDate {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "calendar")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                                Text(DateFormatters.displayDateFormatter.string(from: nextDate))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Spacer()

                        Text(String(format: String(localized: "loan.remainingShort", defaultValue: "%d left"), remaining))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }
    }

    /// "Closed 15 Jun 2026" when we know the final payment date, otherwise just the
    /// status — `lastPaymentDate` is nil for loans marked paid off via the schedule
    /// reset rather than an actual payment.
    private func closedFooterText(loanInfo: LoanInfo) -> String {
        guard let lastPaymentDate = loanInfo.lastPaymentDate,
              let date = DateFormatters.dateFormatter.date(from: lastPaymentDate) else {
            return String(localized: "loan.statusPaidOff", defaultValue: "Paid off")
        }
        return String(
            format: String(localized: "loan.closedOn", defaultValue: "Closed %@"),
            DateFormatters.displayDateFormatter.string(from: date)
        )
    }
}
