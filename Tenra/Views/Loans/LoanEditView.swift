//
//  LoanEditView.swift
//  Tenra
//
//  View for creating, editing, and converting accounts to loans/installments.
//  3 modes: new, edit, convert (mirrors DepositEditView pattern).
//  Migrated to hero-style UI with EditableHeroSection.
//

import SwiftUI

struct LoanEditView: View {
    let loansViewModel: LoansViewModel
    let account: Account?
    let onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var principalAmountText: String = ""
    @State private var currency: String = "KZT"
    @State private var selectedIconSource: IconSource? = nil
    @State private var loanType: LoanType = .annuity
    @State private var interestRateText: String = ""
    @State private var termMonthsText: String = ""
    @State private var paymentDay: Int = 1
    @State private var startDate: Date = Date()
    @State private var validationError: String? = nil


    /// True when converting a regular account → loan (account exists but has no loanInfo)
    private var isConverting: Bool {
        account != nil && account?.loanInfo == nil
    }

    private var isEditing: Bool {
        account != nil && account?.loanInfo != nil
    }

    private var title: String {
        if isConverting {
            return String(localized: "loan.convertTitle", defaultValue: "Convert to Loan")
        } else if isEditing {
            return String(localized: "loan.editTitle", defaultValue: "Edit Loan")
        } else {
            return String(localized: "loan.newTitle", defaultValue: "New Loan")
        }
    }

    private var isSaveDisabled: Bool {
        name.isEmpty || bankName.isEmpty || principalAmountText.isEmpty || termMonthsText.isEmpty
        || (loanType == .annuity && interestRateText.isEmpty)
    }

    var body: some View {
        EditSheetContainer(
            title: title,
            isSaveDisabled: isSaveDisabled,
            wrapInForm: false,
            onSave: saveLoan,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Hero Section: Icon, Name, Amount, Currency
                    EditableHeroSection(
                        iconSource: $selectedIconSource,
                        title: $name,
                        balance: $principalAmountText,
                        currency: $currency,
                        titlePlaceholder: String(localized: "loan.namePlaceholder", defaultValue: "e.g. Car Loan"),
                        config: .accountHero
                    )

                    // Validation Error
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                            .padding(.horizontal, AppSpacing.lg)
                    }

                    // Loan details: bank, type, interest rate
                    FormSection(header: String(localized: "loan.detailsSection", defaultValue: "Loan Details")) {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("building.columns", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.bankLabel", defaultValue: "Bank"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.bankPlaceholder", defaultValue: "Bank name"),
                                text: $bankName
                            )
                            .inlineFieldStyle()
                        }

                        Divider()

                        // Loan type segmented picker
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Picker(String(localized: "loan.typePicker", defaultValue: "Type"), selection: $loanType) {
                                Text(String(localized: "loan.typeAnnuity", defaultValue: "Annuity (Credit)")).tag(LoanType.annuity)
                                Text(String(localized: "loan.typeInstallment", defaultValue: "Installment")).tag(LoanType.installment)
                            }
                            .pickerStyle(.segmented)
                            .disabled(isEditing)

                            if isEditing {
                                Text(String(localized: "loan.typeLockedHint", defaultValue: "Loan type cannot be changed after creation"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            } else if loanType == .installment {
                                Text(String(localized: "loan.installmentHint", defaultValue: "Installment = 0% interest, equal payments"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding(.vertical, AppSpacing.sm)
                        .padding(.horizontal, AppSpacing.lg)

                        if loanType == .annuity {
                            Divider()

                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("percent", color: AppColors.accent, size: AppIconSize.lg)
                            ) {
                                Text(String(localized: "loan.interestRateLabel", defaultValue: "Interest rate"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
                                HStack(spacing: AppSpacing.xs) {
                                    TextField("0.0", text: $interestRateText)
                                        .inlineFieldStyle(keyboard: .decimalPad, maxWidth: 80)
                                    Text(String(localized: "loan.rateAnnualSuffix", defaultValue: "% annual"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                    }

                    // Loan schedule: term, payment day, start date
                    FormSection(header: String(localized: "loan.scheduleSection", defaultValue: "Schedule")) {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("clock", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.termLabel", defaultValue: "Term"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField("0", text: $termMonthsText)
                                    .inlineFieldStyle(keyboard: .numberPad, maxWidth: 60)
                                Text(String(localized: "loan.months", defaultValue: "months"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Divider()

                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("calendar.badge.clock", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.paymentDay", defaultValue: "Payment day"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.sm) {
                                Text("\(paymentDay)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(minWidth: 28, alignment: .trailing)
                                Stepper("", value: $paymentDay, in: 1...31)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }

                        if !isEditing {
                            Divider()
                            DatePickerRow(
                                icon: "calendar",
                                title: String(localized: "loan.startDate", defaultValue: "Loan start date"),
                                selection: $startDate
                            )
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .onAppear {
            if let account = account, let loanInfo = account.loanInfo {
                // Editing existing loan
                name = account.name
                bankName = loanInfo.bankName
                principalAmountText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue)
                currency = account.currency
                selectedIconSource = account.iconSource
                loanType = loanInfo.loanType
                interestRateText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.interestRateAnnual).doubleValue)
                termMonthsText = "\(loanInfo.termMonths)"
                paymentDay = loanInfo.paymentDay
                if let start = DateFormatters.dateFormatter.date(from: loanInfo.startDate) {
                    startDate = start
                }
            } else if let account = account {
                // Converting regular account → loan: pre-fill from account
                name = account.name
                currency = account.currency
                selectedIconSource = account.iconSource
                principalAmountText = String(format: "%.2f", account.balance)
            } else {
                // New loan
                currency = "KZT"
                selectedIconSource = nil
                principalAmountText = ""
                interestRateText = ""
                termMonthsText = ""
                paymentDay = 1
                startDate = Date()
            }
        }
    }

    // MARK: - Save

    private func saveLoan() {
        guard let principalAmount = AmountFormatter.parse(principalAmountText) else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidAmount", defaultValue: "Enter a valid amount")
            }
            HapticManager.error()
            return
        }
        guard let termMonths = Int(termMonthsText), termMonths > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidTerm", defaultValue: "Enter a valid term")
            }
            HapticManager.error()
            return
        }

        let interestRate: Decimal
        if loanType == .annuity {
            guard let rate = AmountFormatter.parse(interestRateText) else {
                withAnimation(AppAnimation.contentSpring) {
                    validationError = String(localized: "loan.error.invalidRate", defaultValue: "Enter a valid interest rate")
                }
                HapticManager.error()
                return
            }
            interestRate = rate
        } else {
            interestRate = 0
        }
        validationError = nil

        let existingInfo = account?.loanInfo
        let startDateStr = isEditing
            ? (existingInfo?.startDate ?? DateFormatters.dateFormatter.string(from: startDate))
            : DateFormatters.dateFormatter.string(from: startDate)

        let loanInfo = LoanInfo(
            bankName: bankName,
            loanType: loanType,
            originalPrincipal: principalAmount,
            remainingPrincipal: existingInfo?.remainingPrincipal ?? principalAmount,
            interestRateAnnual: interestRate,
            interestRateHistory: existingInfo?.interestRateHistory,
            totalInterestPaid: existingInfo?.totalInterestPaid ?? 0,
            termMonths: termMonths,
            startDate: startDateStr,
            endDate: existingInfo?.endDate,
            monthlyPayment: existingInfo?.monthlyPayment,
            paymentDay: paymentDay,
            paymentsMade: existingInfo?.paymentsMade ?? 0,
            lastPaymentDate: existingInfo?.lastPaymentDate,
            lastReconciliationDate: existingInfo?.lastReconciliationDate,
            earlyRepayments: existingInfo?.earlyRepayments ?? []
        )

        let balance = NSDecimalNumber(decimal: principalAmount).doubleValue
        let newAccount = Account(
            id: account?.id ?? UUID().uuidString,
            name: name,
            currency: currency,
            iconSource: selectedIconSource,
            loanInfo: loanInfo,
            shouldCalculateFromTransactions: false,
            initialBalance: balance,
            order: account?.order
        )

        HapticManager.success()
        onSave(newAccount)
    }
}

// MARK: - Previews

#Preview("Loan Edit - New") {
    let coordinator = AppCoordinator()

    LoanEditView(
        loansViewModel: coordinator.loansViewModel,
        account: nil,
        onSave: { _ in }
    )
}

#Preview("Loan Edit - Edit") {
    let coordinator = AppCoordinator()
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

    LoanEditView(
        loansViewModel: coordinator.loansViewModel,
        account: sampleAccount,
        onSave: { _ in }
    )
}
