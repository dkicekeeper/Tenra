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
            let progress = LoanPaymentService.progressPercentage(loanInfo: loanInfo)
            let nextDate = LoanPaymentService.nextPaymentDate(loanInfo: loanInfo)
            let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Header: icon + name + bank + type badge
                HStack(alignment: .top) {
                    IconView(source: loan.iconSource, size: AppIconSize.xl)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loan.name)
                            .font(AppTypography.h4)
                        Text(loanInfo.bankName)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    LoanTypeBadge(loanType: loanInfo.loanType)
                }

                // Progress
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text(Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue, currency: loan.currency))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue, currency: loan.currency))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    ProgressView(value: progress)
                        .tint(AppColors.income)
                        .accessibilityValue(String(format: "%.0f%%", progress * 100))
                }

                // Footer: next payment + remaining
                HStack {
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
            .padding(AppSpacing.lg)
            .cardStyle()
        }
    }
}
