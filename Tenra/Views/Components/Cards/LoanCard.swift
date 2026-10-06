//
//  LoanCard.swift
//  Tenra
//
//  Card displaying loan summary: icon, name, bank, type badge, this month's payment status,
//  progress bar, next payment date, and remaining count. Adapter over DesignKit's
//  `PayoffProgressCard`: the payment maths, the copy and the badges stay here.
//

import SwiftUI

struct LoanCard: View {
    let loan: Account
    /// This month's regular payment (`LoanMonthStatusService.status`). nil shows no status
    /// badge: closed, not started, or no payment due this month.
    var monthStatus: LoanMonthStatus? = nil

    var body: some View {
        if let loanInfo = loan.loanInfo {
            let isPaidOff = loanInfo.isPaidOff
            let progress = isPaidOff ? 1.0 : LoanPaymentService.progressPercentage(loanInfo: loanInfo)
            // With a status, the date is the payment still to make: this month's while unpaid
            // (even when overdue), next month's once paid.
            let nextDate: Date? = isPaidOff
                ? nil
                : (monthStatus?.nextDueDate ?? LoanPaymentService.nextPaymentDate(loanInfo: loanInfo))
            let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)

            PayoffProgressCard(
                iconSource: loan.iconSource,
                title: loan.name,
                subtitle: loanInfo.bankName,
                remaining: NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue,
                total: NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue,
                currency: loan.currency,
                progress: progress,
                // A closed loan has no next payment or count: it shows when it was paid off.
                phase: isPaidOff
                    ? .done(caption: closedFooterText(loanInfo: loanInfo))
                    : .inProgress(
                        nextDate: nextDate.map { DateFormatters.displayDateFormatter.string(from: $0) },
                        remainingCaption: String(
                            format: String(localized: "loan.remainingShort", defaultValue: "%d left"),
                            remaining
                        )
                    )
            ) {
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    LoanTypeBadge(loanType: loanInfo.loanType, isPaidOff: isPaidOff)
                    if let monthStatus {
                        LoanMonthStatusBadge(status: monthStatus)
                    }
                }
            }
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
