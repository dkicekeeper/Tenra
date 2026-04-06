//
//  LoanPaymentView.swift
//  Tenra
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

    private var scheduledHint: String {
        String(
            format: String(localized: "loan.scheduledPayment", defaultValue: "Scheduled: %@"),
            Formatting.formatCurrency(
                NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue,
                currency: account.currency
            )
        )
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.paymentTitle", defaultValue: "Loan Payment"),
            isSaveDisabled: !isFormValid,
            wrapInForm: false,
            onSave: { savePayment() },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                    }

                    // Amount + Source + Date in one card
                    FormSection {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("banknote", color: AppColors.textSecondary, size: AppIconSize.md),
                            hint: scheduledHint
                        ) {
                            Text(String(localized: "loan.amountLabel", defaultValue: "Amount"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField(
                                    String(localized: "loan.amountPlaceholder", defaultValue: "Amount"),
                                    text: $amountText
                                )
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .multilineTextAlignment(.trailing)
                                .font(AppTypography.bodySmall)
                                Text(Formatting.currencySymbol(for: account.currency))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        if availableAccounts.isEmpty {
                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("building.columns", color: AppColors.textSecondary, size: AppIconSize.md)
                            ) {
                                Text(String(localized: "loan.sourceAccount", defaultValue: "From account"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
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

                    // Impact preview (conditional second section)
                    if let amount = AmountFormatter.parse(amountText), amount > 0 {
                        let breakdown = LoanPaymentService.paymentBreakdown(
                            remainingPrincipal: loanInfo.remainingPrincipal,
                            annualRate: loanInfo.interestRateAnnual,
                            monthlyPayment: amount
                        )
                        FormSection(header: String(localized: "loan.impact", defaultValue: "Impact")) {
                            InfoRow(
                                icon: "percent",
                                label: String(localized: "loan.interestPortion", defaultValue: "Interest"),
                                value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.interest).doubleValue, currency: account.currency)
                            )
                            Divider().padding(.leading, AppSpacing.lg)
                            InfoRow(
                                icon: "arrow.down.to.line",
                                label: String(localized: "loan.principalPortion", defaultValue: "Principal"),
                                value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.principal).doubleValue, currency: account.currency)
                            )
                        }
                    }
                }
                .padding(AppSpacing.lg)
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
