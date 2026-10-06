//
//  LoanMonthStatusBadge.swift
//  Tenra
//
//  Capsule badge for a loan's regular payment this month: "Paid this month" or "Not paid".
//  Adapter over DesignKit's `BadgeView` (tinted), like `LoanTypeBadge`: maps the status to
//  its label and colour. The date that goes with it (this month's payment day while unpaid,
//  next month's once paid) is shown by the caller from `LoanMonthStatus.nextDueDate`.
//

import SwiftUI

struct LoanMonthStatusBadge: View {
    let status: LoanMonthStatus

    private var label: String {
        switch status {
        case .paid:
            return String(localized: "loan.statusPaidThisMonth", defaultValue: "Paid this month")
        case .unpaid:
            return String(localized: "loan.statusNotPaid", defaultValue: "Not paid")
        }
    }

    /// Green like "Paid off"; orange while the payment day is still ahead, red once it has passed.
    private var tint: Color {
        switch status {
        case .paid:
            return AppColors.income
        case .unpaid(_, let isOverdue):
            return isOverdue ? AppColors.destructive : AppColors.warning
        }
    }

    var body: some View {
        BadgeView(label, color: tint)
    }
}
