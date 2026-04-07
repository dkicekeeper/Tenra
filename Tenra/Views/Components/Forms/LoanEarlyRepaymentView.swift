//
//  LoanEarlyRepaymentView.swift
//  Tenra
//
//  View for making early repayments on loans.
//  Shows impact on remaining term or monthly payment.
//

import SwiftUI

struct LoanEarlyRepaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let onRepayment: (Decimal, String, EarlyRepaymentType, String?) -> Void // (amount, date, type, note)

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var repaymentDate: Date = Date()
    @State private var repaymentType: EarlyRepaymentType = .reduceTerm
    @State private var noteText: String = ""
    @FocusState private var isAmountFocused: Bool
    @State private var validationError: String? = nil

    private var remainingHint: String {
        String(
            format: String(localized: "loan.remainingBalance", defaultValue: "Remaining: %@"),
            Formatting.formatCurrency(
                NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue,
                currency: account.currency
            )
        )
    }

    private var strategyHint: String {
        repaymentType == .reduceTerm
            ? String(localized: "loan.reduceTermHint", defaultValue: "Keep monthly payment, finish sooner")
            : String(localized: "loan.reducePaymentHint", defaultValue: "Keep term, lower monthly payment")
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.earlyRepaymentTitle", defaultValue: "Early Repayment"),
            isSaveDisabled: amountText.isEmpty,
            wrapInForm: false,
            onSave: { saveRepayment() },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                    }

                    // Amount + Date + Strategy + Note in one card
                    FormSection {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("banknote", color: AppColors.accent, size: AppIconSize.lg),
                            hint: remainingHint
                        ) {
                            Text(String(localized: "loan.amountLabel", defaultValue: "Amount"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField(
                                    String(localized: "loan.amountPlaceholder", defaultValue: "Amount"),
                                    text: $amountText
                                )
                                .inlineFieldStyle(keyboard: .decimalPad)
                                .focused($isAmountFocused)
                                Text(Formatting.currencySymbol(for: account.currency))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "loan.date", defaultValue: "Date"),
                            selection: $repaymentDate
                        )

                        Divider().padding(.leading, AppSpacing.lg)

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Picker(String(localized: "loan.strategy", defaultValue: "Strategy"), selection: $repaymentType) {
                                Text(String(localized: "loan.reduceTerm", defaultValue: "Reduce Term")).tag(EarlyRepaymentType.reduceTerm)
                                Text(String(localized: "loan.reducePayment", defaultValue: "Reduce Payment")).tag(EarlyRepaymentType.reducePayment)
                            }
                            .pickerStyle(.segmented)
                            Text(strategyHint)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.vertical, AppSpacing.sm)
                        .padding(.horizontal, AppSpacing.lg)

                        Divider().padding(.leading, AppSpacing.lg)

                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("note.text", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.noteLabel", defaultValue: "Note"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.notePlaceholder", defaultValue: "Optional"),
                                text: $noteText,
                                axis: .vertical
                            )
                            .inlineNoteStyle()
                        }
                    }

                    // Impact preview (conditional second section)
                    if let amount = AmountFormatter.parse(amountText), amount > 0, amount <= loanInfo.remainingPrincipal {
                        FormSection(header: String(localized: "loan.impact", defaultValue: "Impact")) {
                            impactPreview(amount: amount)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .task {
            await Task.yield()
            isAmountFocused = true
        }
    }

    private func computePreview(amount: Decimal) -> LoanInfo {
        var preview = loanInfo
        let dateStr = DateFormatters.dateFormatter.string(from: repaymentDate)
        LoanPaymentService.applyEarlyRepayment(
            loanInfo: &preview,
            amount: amount,
            date: dateStr,
            type: repaymentType
        )
        return preview
    }

    @ViewBuilder
    private func impactPreview(amount: Decimal) -> some View {
        let preview = computePreview(amount: amount)

        switch repaymentType {
        case .reduceTerm:
            InfoRow(
                icon: "calendar.badge.minus",
                label: String(localized: "loan.termReduction", defaultValue: "Term reduced by"),
                value: String(format: String(localized: "loan.monthsValue", defaultValue: "%d months"), loanInfo.termMonths - preview.termMonths)
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            Divider()
                .padding(.leading, AppSpacing.lg)
            InfoRow(
                icon: "calendar",
                label: String(localized: "loan.newEndDate", defaultValue: "New end date"),
                value: formatDateString(preview.endDate)
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        case .reducePayment:
            InfoRow(
                icon: "arrow.down.circle",
                label: String(localized: "loan.paymentReduction", defaultValue: "Payment reduced by"),
                value: Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.monthlyPayment - preview.monthlyPayment).doubleValue, currency: account.currency)
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            Divider()
                .padding(.leading, AppSpacing.lg)
            InfoRow(
                icon: "banknote",
                label: String(localized: "loan.newMonthlyPayment", defaultValue: "New monthly payment"),
                value: Formatting.formatCurrency(NSDecimalNumber(decimal: preview.monthlyPayment).doubleValue, currency: account.currency)
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private func saveRepayment() {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidAmount", defaultValue: "Enter a valid amount")
            }
            HapticManager.error()
            return
        }
        guard amount <= loanInfo.remainingPrincipal else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.exceedsRemaining", defaultValue: "Amount exceeds remaining balance")
            }
            HapticManager.error()
            return
        }
        validationError = nil

        let dateStr = DateFormatters.dateFormatter.string(from: repaymentDate)
        let note = noteText.isEmpty ? nil : noteText

        onRepayment(amount, dateStr, repaymentType, note)
        HapticManager.success()
        dismiss()
    }

    private func formatDateString(_ dateStr: String) -> String {
        DateFormatters.displayString(from: dateStr)
    }
}

// MARK: - Previews

#Preview("Early Repayment") {
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

    LoanEarlyRepaymentView(
        account: sampleAccount,
        loanInfo: sampleAccount.loanInfo!,
        onRepayment: { _, _, _, _ in }
    )
}
