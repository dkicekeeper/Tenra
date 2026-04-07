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

    var body: some View {
        Text(loanType == .annuity
             ? String(localized: "loan.typeAnnuityShort", defaultValue: "Credit")
             : String(localized: "loan.typeInstallmentShort", defaultValue: "Installment"))
            .font(AppTypography.bodySmall)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(
                (loanType == .annuity ? AppColors.expense : AppColors.planned)
                    .opacity(0.15)
            )
            .clipShape(Capsule())
    }
}
