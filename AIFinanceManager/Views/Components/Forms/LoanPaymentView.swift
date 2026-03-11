//
//  LoanPaymentView.swift
//  AIFinanceManager
//
//  View for making a manual monthly loan payment.
//  Selects a source bank account and records the payment.
//

import SwiftUI

struct LoanPaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let availableAccounts: [Account]
    let onPayment: (Decimal, String, String) -> Void // (amount, date, sourceAccountId)

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var paymentDate: Date = Date()
    @State private var selectedSourceAccountId: String = ""
    @FocusState private var isAmountFocused: Bool

    @State private var validationError: String? = nil

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.paymentTitle", defaultValue: "Loan Payment"),
            isSaveDisabled: !isFormValid,
            onSave: { savePayment() },
            onCancel: { dismiss() }
        ) {
            if let error = validationError {
                InlineStatusText(message: error, type: .error)
            }

            Section(header: Text(String(localized: "loan.paymentAmount", defaultValue: "Payment Amount"))) {
                HStack {
                    TextField(String(localized: "loan.amountPlaceholder", defaultValue: "Amount"), text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                    Text(Formatting.currencySymbol(for: account.currency))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Text(String(format: String(localized: "loan.scheduledPayment", defaultValue: "Scheduled: %@"), Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue, currency: account.currency)))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Section(header: Text(String(localized: "loan.sourceAccount", defaultValue: "Source Account"))) {
                if availableAccounts.isEmpty {
                    Text(String(localized: "loan.noSourceAccounts", defaultValue: "No accounts available"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Picker(String(localized: "loan.selectSourceAccount", defaultValue: "Select account to pay from"), selection: $selectedSourceAccountId) {
                        Text(String(localized: "loan.selectSourceAccount", defaultValue: "Select account to pay from"))
                            .tag("")
                        ForEach(availableAccounts) { acc in
                            Text(acc.name)
                                .tag(acc.id)
                        }
                    }
                }
            }

            Section(header: Text(String(localized: "loan.repaymentDate", defaultValue: "Date"))) {
                DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $paymentDate, displayedComponents: .date)
            }

            // Payment breakdown preview
            if let amount = AmountFormatter.parse(amountText), amount > 0 {
                Section(header: Text(String(localized: "loan.impact", defaultValue: "Impact"))) {
                    let breakdown = LoanPaymentService.paymentBreakdown(
                        remainingPrincipal: loanInfo.remainingPrincipal,
                        annualRate: loanInfo.interestRateAnnual,
                        monthlyPayment: amount
                    )
                    InfoRow(
                        icon: "percent",
                        label: String(localized: "loan.interestPortion", defaultValue: "Interest"),
                        value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.interest).doubleValue, currency: account.currency)
                    )
                    InfoRow(
                        icon: "arrow.down.to.line",
                        label: String(localized: "loan.principalPortion", defaultValue: "Principal"),
                        value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.principal).doubleValue, currency: account.currency)
                    )
                }
            }
        }
        .onAppear {
            amountText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue)
            if selectedSourceAccountId.isEmpty, let first = availableAccounts.first {
                selectedSourceAccountId = first.id
            }
        }
        .task {
            await Task.yield()
            isAmountFocused = true
        }
    }

    private var isFormValid: Bool {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return false }
        return !selectedSourceAccountId.isEmpty
    }

    private func savePayment() {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidAmount", defaultValue: "Enter a valid amount")
            }
            HapticManager.error()
            return
        }
        guard !selectedSourceAccountId.isEmpty else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.noSourceAccount", defaultValue: "Select a source account")
            }
            HapticManager.error()
            return
        }
        validationError = nil

        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
        onPayment(amount, dateStr, selectedSourceAccountId)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Loan Payment") {
    let sampleLoanAccount = Account(
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

    let sourceAccount = Account(
        id: "source-1",
        name: "Kaspi Gold",
        currency: "KZT",
        initialBalance: 500_000
    )

    LoanPaymentView(
        account: sampleLoanAccount,
        loanInfo: sampleLoanAccount.loanInfo!,
        availableAccounts: [sourceAccount],
        onPayment: { _, _, _ in }
    )
}
