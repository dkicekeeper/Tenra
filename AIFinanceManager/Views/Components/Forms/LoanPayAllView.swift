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
            wrapInForm: false,
            onSave: { savePayAll() },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Loans + Total in one card
                    FormSection(header: String(localized: "loan.payAllLoans", defaultValue: "Loans")) {
                        ForEach(Array(activeLoans.enumerated()), id: \.element.id) { index, loan in
                            if let loanInfo = loan.loanInfo {
                                if index > 0 {
                                    Divider().padding(.leading, AppSpacing.lg)
                                }
                                UniversalRow(
                                    config: .standard,
                                    leadingIcon: .custom(source: loan.iconSource, style: .roundedLogo(size: AppIconSize.lg))
                                ) {
                                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                        Text(loan.name)
                                            .font(AppTypography.body)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text(loanInfo.bankName)
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                } trailing: {
                                    FormattedAmountText(
                                        amount: NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue,
                                        currency: loan.currency,
                                        fontSize: AppTypography.bodySmall,
                                        color: AppColors.expense
                                    )
                                }
                            }
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        FormLabeledRow(icon: "sum", label: String(localized: "loan.payAllTotal", defaultValue: "Total")) {
                            FormattedAmountText(
                                amount: NSDecimalNumber(decimal: totalPayment).doubleValue,
                                currency: currency,
                                fontSize: AppTypography.bodySmall,
                                color: AppColors.expense
                            )
                        }
                    }

                    // Source account + Date in one card
                    FormSection(header: String(localized: "loan.paymentSection", defaultValue: "Payment")) {
                        if availableAccounts.isEmpty {
                            FormLabeledRow(icon: "building.columns", label: String(localized: "loan.sourceAccount", defaultValue: "From account")) {
                                Text(String(localized: "loan.noSourceAccounts", defaultValue: "No accounts"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } else {
                            MenuPickerRow(
                                icon: "building.columns",
                                title: String(localized: "loan.sourceAccount", defaultValue: "From account"),
                                selection: $selectedSourceAccountId,
                                options: availableAccounts.map { (label: $0.name, value: $0.id) }
                            )
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "loan.date", defaultValue: "Date"),
                            selection: $paymentDate
                        )
                    }
                }
                .padding(AppSpacing.lg)
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
