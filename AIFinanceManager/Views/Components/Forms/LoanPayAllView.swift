//
//  LoanPayAllView.swift
//  AIFinanceManager
//
//  View for paying all monthly loan payments at once
//  from a selected source bank account.
//

import SwiftUI

struct LoanPayAllView: View {
    let activeLoans: [Account]
    let availableAccounts: [Account]
    let currency: String
    let onPayAll: (String, String) -> Void // (sourceAccountId, dateStr)

    @Environment(\.dismiss) private var dismiss

    @State private var paymentDate: Date = Date()
    @State private var selectedSourceAccountId: String = ""

    private var totalPayment: Decimal {
        activeLoans.compactMap { $0.loanInfo?.monthlyPayment }.reduce(0, +)
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.payAllTitle", defaultValue: "Pay All Loans"),
            isSaveDisabled: selectedSourceAccountId.isEmpty || activeLoans.isEmpty,
            onSave: { savePayAll() },
            onCancel: { dismiss() }
        ) {
            // Loan list
            Section(header: Text(String(localized: "loan.payAllLoans", defaultValue: "Loans"))) {
                ForEach(activeLoans) { loan in
                    if let loanInfo = loan.loanInfo {
                        HStack {
                            IconView(source: loan.iconSource, size: AppIconSize.md)

                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(loan.name)
                                    .font(AppTypography.bodySmall)
                                Text(loanInfo.bankName)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            FormattedAmountText(amount: NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue, currency: loan.currency, fontSize: AppTypography.bodySmall, color: AppColors.expense)
                        }
                    }
                }
            }

            // Total
            Section {
                HStack {
                    Text(String(localized: "loan.payAllTotal", defaultValue: "Total Payment"))
                        .font(AppTypography.bodyEmphasis)
                    Spacer()
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: totalPayment).doubleValue,
                        currency: currency,
                        fontSize: AppTypography.bodyEmphasis,
                        color: AppColors.expense
                    )
                }
            }

            // Source account
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

            // Date
            Section(header: Text(String(localized: "loan.repaymentDate", defaultValue: "Date"))) {
                DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $paymentDate, displayedComponents: .date)
            }
        }
        .onAppear {
            if selectedSourceAccountId.isEmpty, let first = availableAccounts.first {
                selectedSourceAccountId = first.id
            }
        }
    }

    // MARK: - Actions

    private func savePayAll() {
        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
        onPayAll(selectedSourceAccountId, dateStr)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Pay All Loans") {
    let loan1 = Account(
        id: "loan-1",
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

    let loan2 = Account(
        id: "loan-2",
        name: "Phone Installment",
        currency: "KZT",
        loanInfo: LoanInfo(
            bankName: "Kaspi Bank",
            loanType: .installment,
            originalPrincipal: 450_000,
            remainingPrincipal: 300_000,
            termMonths: 12,
            startDate: "2025-09-01",
            paymentDay: 5,
            paymentsMade: 4
        ),
        initialBalance: 450_000
    )

    let sourceAccount = Account(
        id: "source-1",
        name: "Kaspi Gold",
        currency: "KZT",
        initialBalance: 500_000
    )

    LoanPayAllView(
        activeLoans: [loan1, loan2],
        availableAccounts: [sourceAccount],
        currency: "KZT",
        onPayAll: { _, _ in }
    )
}
