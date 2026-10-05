//
//  LoanTypeBadge.swift
//  Tenra
//
//  Capsule badge displaying loan type (Credit / Installment) or "Paid off".
//  Adapter over DesignKit's `BadgeView` (tinted): maps the loan type to its label and colour.
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
        BadgeView(label, color: tint)
    }
}
