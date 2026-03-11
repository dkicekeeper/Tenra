//
//  LoanRateChangeView.swift
//  AIFinanceManager
//
//  Rate change view for loans (mirrors DepositRateChangeView pattern)
//

import SwiftUI

struct LoanRateChangeView: View {
    let account: Account
    let onRateChanged: (String, Decimal, String?) -> Void // (effectiveFrom, annualRate, note)

    @Environment(\.dismiss) private var dismiss

    @State private var rateText: String = ""
    @State private var effectiveFromDate: Date = Date()
    @State private var noteText: String = ""
    @FocusState private var isRateFocused: Bool

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.changeRateTitle", defaultValue: "Change Rate"),
            isSaveDisabled: rateText.isEmpty,
            onSave: { saveRateChange() },
            onCancel: { dismiss() }
        ) {
            Section(header: Text(String(localized: "loan.newRate", defaultValue: "New Interest Rate"))) {
                HStack {
                    TextField("0.0", text: $rateText)
                        .keyboardType(.decimalPad)
                        .focused($isRateFocused)
                    Text(String(localized: "loan.rateAnnual", defaultValue: "% annual"))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Section(header: Text(String(localized: "loan.effectiveDate", defaultValue: "Effective From"))) {
                DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $effectiveFromDate, displayedComponents: .date)
            }

            if let loanInfo = account.loanInfo {
                Section(header: Text(String(localized: "loan.rateChangeImpact", defaultValue: "Impact"))) {
                    if let newRate = AmountFormatter.parse(rateText), newRate > 0 {
                        let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)
                        let newPayment = LoanPaymentService.calculateMonthlyPayment(
                            principal: loanInfo.remainingPrincipal,
                            annualRate: newRate,
                            termMonths: remaining
                        )
                        let diff = newPayment - loanInfo.monthlyPayment

                        InfoRow(
                            icon: "banknote",
                            label: String(localized: "loan.newMonthlyPayment", defaultValue: "New monthly payment"),
                            value: Formatting.formatCurrency(NSDecimalNumber(decimal: newPayment).doubleValue, currency: account.currency)
                        )

                        let diffAmount = NSDecimalNumber(decimal: diff).doubleValue
                        InfoRow(
                            icon: diff > 0 ? "arrow.up" : "arrow.down",
                            label: String(localized: "loan.paymentChange", defaultValue: "Change"),
                            value: String(format: "%@%@", diff > 0 ? "+" : "", Formatting.formatCurrency(diffAmount, currency: account.currency))
                        )
                    } else {
                        Text(String(localized: "loan.enterRateForPreview", defaultValue: "Enter rate to see impact"))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Section(header: Text(String(localized: "loan.note", defaultValue: "Note"))) {
                TextField(String(localized: "loan.notePlaceholder", defaultValue: "Optional note"), text: $noteText, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .onAppear {
            if let loanInfo = account.loanInfo {
                rateText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.interestRateAnnual).doubleValue)
            }
        }
        .task {
            await Task.yield()
            isRateFocused = true
        }
    }

    private func saveRateChange() {
        guard let rate = AmountFormatter.parse(rateText) else { return }

        let dateString = DateFormatters.dateFormatter.string(from: effectiveFromDate)
        let note = noteText.isEmpty ? nil : noteText

        onRateChanged(dateString, rate, note)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Loan Rate Change") {
    let sampleAccount = Account(
        id: "preview-loan",
        name: "Car Loan",
        currency: "KZT",
        iconSource: .bankLogo(.halykBank),
        loanInfo: LoanInfo(
            bankName: "Halyk Bank",
            loanType: .annuity,
            originalPrincipal: 5_000_000,
            remainingPrincipal: 3_500_000,
            interestRateAnnual: 18.5,
            termMonths: 36,
            startDate: "2025-06-01",
            paymentDay: 15,
            paymentsMade: 9
        ),
        initialBalance: 5_000_000
    )

    LoanRateChangeView(
        account: sampleAccount,
        onRateChanged: { _, _, _ in }
    )
}
