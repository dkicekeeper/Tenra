//
//  LoanRateChangeView.swift
//  Tenra
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

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.changeRateTitle", defaultValue: "Change Rate"),
            isSaveDisabled: rateText.isEmpty,
            wrapInForm: false,
            onSave: { saveRateChange() },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Rate + Date + Note in one card
                    FormSection {
                        UniversalRow(
                            leadingIcon: .sfSymbol("percent", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "loan.rateLabel", defaultValue: "Annual rate")
                        ) {
                            FormTextField(
                                text: $rateText,
                                placeholder: "0.0",
                                style: .inline,
                                keyboardType: .decimalPad,
                                autofocus: true
                            )
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "loan.effectiveDate", defaultValue: "Effective from"),
                            selection: $effectiveFromDate
                        )

                        Divider().padding(.leading, AppSpacing.lg)

                        UniversalRow(
                            leadingIcon: .sfSymbol("note.text", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "loan.noteLabel", defaultValue: "Note")
                        ) {
                            FormTextField(
                                text: $noteText,
                                placeholder: String(localized: "loan.notePlaceholder", defaultValue: "Optional"),
                                style: .inlineMultiline(min: 1, max: 4)
                            )
                        }
                    }

                    // Impact preview (conditional second section)
                    if let loanInfo = account.loanInfo,
                       let newRate = AmountFormatter.parse(rateText), newRate > 0 {
                        let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)
                        let newPayment = LoanPaymentService.calculateMonthlyPayment(
                            principal: loanInfo.remainingPrincipal,
                            annualRate: newRate,
                            termMonths: remaining
                        )
                        let diff = newPayment - loanInfo.monthlyPayment

                        FormSection(header: String(localized: "loan.rateChangeImpact", defaultValue: "Impact")) {
                            InfoRow(
                                icon: "banknote",
                                label: String(localized: "loan.newMonthlyPayment", defaultValue: "New monthly payment"),
                                amount: NSDecimalNumber(decimal: newPayment).doubleValue,
                                currency: account.currency
                            )
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                            Divider().padding(.leading, AppSpacing.lg)
                            InfoRow(
                                icon: diff > 0 ? "arrow.up" : "arrow.down",
                                label: String(localized: "loan.paymentChange", defaultValue: "Change"),
                                amount: NSDecimalNumber(decimal: diff).doubleValue,
                                currency: account.currency,
                                prefix: diff > 0 ? "+" : ""
                            )
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .onAppear {
            if let loanInfo = account.loanInfo {
                rateText = AmountInputFormatting.bindingString(for: loanInfo.interestRateAnnual)
            }
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
        iconSource: .brandService("halykbank.kz"),
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
