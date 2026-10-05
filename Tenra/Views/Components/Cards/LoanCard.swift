//
//  LoanCard.swift
//  Tenra
//
//  Card displaying loan summary: icon, name, bank, type badge,
//  progress bar, next payment date, and remaining count. Adapter over DesignKit's
//  `PayoffProgressCard`: the payment maths, the copy and `LoanTypeBadge` stay here.
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
                LoanTypeBadge(loanType: loanInfo.loanType, isPaidOff: isPaidOff)
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
