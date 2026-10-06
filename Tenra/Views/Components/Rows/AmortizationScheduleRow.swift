//
//  AmortizationScheduleRow.swift
//  Tenra
//
//  One loan amortization-schedule entry: payment number + date, payment amount (and the
//  interest portion, if any), a paid/upcoming indicator; unpaid rows are dimmed. Adapter
//  over DesignKit's `ScheduleRow`.
//

import SwiftUI

struct AmortizationScheduleRow: View {
    let entry: LoanPaymentService.AmortizationEntry
    let currency: String
    @Environment(\.amountsHidden) private var amountsHidden

    var body: some View {
        ScheduleRow(
            title: "#\(entry.paymentNumber)",
            subtitle: DateFormatters.displayString(from: entry.date),
            amount: NSDecimalNumber(decimal: entry.payment).doubleValue,
            currency: currency,
            detail: interestText,
            isDone: entry.isPaid
        )
    }

    private var interestText: String? {
        guard entry.interest > 0 else { return nil }
        return String(
            format: String(localized: "loan.interestShort", defaultValue: "int: %@"),
            amountsHidden ? Formatting.hiddenAmount(currency: currency) : Formatting.formatCurrencySmart(
                NSDecimalNumber(decimal: entry.interest).doubleValue,
                currency: currency
            )
        )
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
