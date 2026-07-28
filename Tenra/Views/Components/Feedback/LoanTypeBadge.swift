//
//  LoanTypeBadge.swift
//  Tenra
//
//  Capsule badge displaying loan type (Credit / Installment)
//  with a tinted background color.
//

import SwiftUI

struct LoanTypeBadge: View {
    let loanType: LoanType

    /// A fully repaid loan shows its status here instead of its type: the type has
    /// stopped mattering, and "closed" is the one thing worth reading at a glance.
    var isPaidOff: Bool = false

    private var label: String {
        if isPaidOff {
            return String(localized: "loan.statusPaidOff", defaultValue: "Paid off")
        }
        return loanType == .annuity
            ? String(localized: "loan.typeAnnuityShort", defaultValue: "Credit")
            : String(localized: "loan.typeInstallmentShort", defaultValue: "Installment")
    }

    private var tint: Color {
        if isPaidOff { return AppColors.income }
        return loanType == .annuity ? AppColors.expense : AppColors.planned
    }

    var body: some View {
        Text(label)
            .font(AppTypography.bodySmall)
            .foregroundStyle(isPaidOff ? AppColors.income : Color.primary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
    }
}
