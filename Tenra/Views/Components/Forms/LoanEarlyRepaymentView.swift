//
//  LoanEarlyRepaymentView.swift
//  Tenra
//
//  Early-repayment composer. Mirrors the TransactionEditView layout
//  (Hero → Amount → Source → Strategy → Category → Subcategory → Note → Impact)
//  so the create flow reads identically to the regular monthly-payment flow
//  apart from the strategy picker (reduce term vs reduce payment).
//

import SwiftUI

/// Outcome of `LoanEarlyRepaymentView` collected on save.
struct LoanEarlyRepaymentFormResult {
    let amount: Decimal
    let date: String
    let type: EarlyRepaymentType
    let sourceAccountId: String
    let note: String?
    /// `nil` keeps the technical default (`Loan Payment`); non-nil values come
    /// from the expense catalog and tag the repayment alongside regular spending.
    let category: String?
    let subcategoryIds: Set<String>
}

struct LoanEarlyRepaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let availableAccounts: [Account]
    let balanceCoordinator: BalanceCoordinator
    let baseCurrency: String
    let appSettings: AppSettings
    var availableCategories: [String] = []
    var customCategories: [CustomCategory] = []
    var categoriesViewModel: CategoriesViewModel? = nil
    var initialCategory: String? = nil
    var initialSubcategoryIds: Set<String> = []
    let onRepayment: (LoanEarlyRepaymentFormResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var selectedCurrency: String = ""
    @State private var repaymentDate: Date = Date()
    @State private var repaymentType: EarlyRepaymentType = .reduceTerm
    @State private var selectedSourceAccountId: String? = nil
    @State private var noteText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var showingSubcategorySearch: Bool = false
    @State private var subcategorySearchText: String = ""
    @State private var validationError: String? = nil

    private var selectedCategoryId: String? {
        guard let name = selectedCategory else { return nil }
        return customCategories.first { $0.name == name }?.id
    }

    private var heroTitle: String {
        String(localized: "transaction.type.loanEarlyRepayment", defaultValue: "Досрочное погашение")
    }

    private var heroIcon: IconSource {
        account.iconSource ?? .sfSymbol("creditcard.fill")
    }

    /// Subtitle shown under the hero: remaining principal so the user knows
    /// the maximum allowable repayment without scrolling away.
    private var heroSubtitle: String {
        let remaining = Formatting.formatCurrencySmart(
            NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue,
            currency: account.currency
        )
        return String(
            format: String(localized: "loan.remainingBalance", defaultValue: "Remaining: %@"),
            remaining
        )
    }

    private var strategyHint: String {
        repaymentType == .reduceTerm
            ? String(localized: "loan.reduceTermHint", defaultValue: "Keep monthly payment, finish sooner")
            : String(localized: "loan.reducePaymentHint", defaultValue: "Keep term, lower monthly payment")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    HeroSection(
                        icon: heroIcon,
                        title: heroTitle,
                        subtitle: heroSubtitle
                    )

                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                            .padding(.horizontal, AppSpacing.pageHorizontal)
                    }

                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $selectedCurrency,
                        errorMessage: nil,
                        baseCurrency: baseCurrency,
                        accountCurrencies: Set([account.currency]),
                        appSettings: appSettings
                    )

                    fromSection
                    strategySection
                    categorySection
                    subcategorySection
                    noteSection
                    impactSection
                }
                .animation(AppAnimation.gentleSpring, value: validationError)
                .animation(AppAnimation.gentleSpring, value: selectedCategory)
                .animation(AppAnimation.gentleSpring, value: amountText)
                .animation(AppAnimation.gentleSpring, value: repaymentType)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .dateButtonsSafeArea(selectedDate: $repaymentDate, isDisabled: !isFormValid) { _ in
                saveRepayment()
            }
            .sheet(isPresented: $showingSubcategorySearch) {
                if let categoriesVM = categoriesViewModel,
                   let categoryId = selectedCategoryId {
                    SubcategorySearchView(
                        categoriesViewModel: categoriesVM,
                        categoryId: categoryId,
                        selectedSubcategoryIds: $selectedSubcategoryIds,
                        searchText: $subcategorySearchText
                    )
                    .onAppear { subcategorySearchText = "" }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onAppear(perform: applyDefaults)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var fromSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "transactionForm.fromHeader"))
                .padding(.horizontal, AppSpacing.lg)

            AccountSelectorView(
                accounts: availableAccounts,
                selectedAccountId: $selectedSourceAccountId,
                emptyStateMessage: String(localized: "loan.noSourceAccounts", defaultValue: "No accounts"),
                balanceCoordinator: balanceCoordinator
            )
        }
    }

    @ViewBuilder
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "loan.strategy", defaultValue: "Strategy"))
                .padding(.horizontal, AppSpacing.lg)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Picker(String(localized: "loan.strategy", defaultValue: "Strategy"), selection: $repaymentType) {
                    Text(String(localized: "loan.reduceTerm", defaultValue: "Reduce Term"))
                        .tag(EarlyRepaymentType.reduceTerm)
                    Text(String(localized: "loan.reducePayment", defaultValue: "Reduce Payment"))
                        .tag(EarlyRepaymentType.reducePayment)
                }
                .pickerStyle(.segmented)

                Text(strategyHint)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .screenPadding()
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        if !availableCategories.isEmpty {
            CategorySelectorView(
                categories: availableCategories,
                type: .expense,
                customCategories: customCategories,
                selectedCategory: $selectedCategory,
                onSelectionChange: { newValue in
                    if newValue != selectedCategory {
                        selectedSubcategoryIds.removeAll()
                    }
                },
                emptyStateMessage: nil
            )
        }
    }

    @ViewBuilder
    private var subcategorySection: some View {
        // Always show the subcategory section when an expense catalog is available
        // — see `LoanPaymentView` for rationale (discoverability before the user
        // picks a category).
        if let categoriesVM = categoriesViewModel, !availableCategories.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SectionHeaderView(String(localized: "loan.subcategoryHeader", defaultValue: "Subcategory"))
                    .padding(.horizontal, AppSpacing.lg)

                if selectedCategoryId != nil {
                    SubcategorySelectorView(
                        categoriesViewModel: categoriesVM,
                        categoryId: selectedCategoryId,
                        selectedSubcategoryIds: $selectedSubcategoryIds,
                        onSearchTap: {
                            withAnimation { showingSubcategorySearch = true }
                        }
                    )
                } else {
                    Text(String(
                        localized: "loan.subcategoryEmpty",
                        defaultValue: "Pick a category above to add subcategory tags"
                    ))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.lg)
                }
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        FormTextField(
            text: $noteText,
            placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
            style: .multiline(min: 2, max: 6)
        )
        .screenPadding()
    }

    @ViewBuilder
    private var impactSection: some View {
        if let amount = AmountFormatter.parse(amountText), amount > 0, amount <= loanInfo.remainingPrincipal {
            FormSection(header: String(localized: "loan.impact", defaultValue: "Impact")) {
                impactRows(for: amount)
            }
            .screenPadding()
        }
    }

    @ViewBuilder
    private func impactRows(for amount: Decimal) -> some View {
        let preview = computePreview(amount: amount)

        switch repaymentType {
        case .reduceTerm:
            InfoRow(
                icon: "calendar.badge.minus",
                label: String(localized: "loan.termReduction", defaultValue: "Term reduced by"),
                value: String(
                    format: String(localized: "loan.monthsValue", defaultValue: "%d months"),
                    loanInfo.termMonths - preview.termMonths
                )
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            Divider().padding(.leading, AppSpacing.lg)
            InfoRow(
                icon: "calendar",
                label: String(localized: "loan.newEndDate", defaultValue: "New end date"),
                value: DateFormatters.displayString(from: preview.endDate)
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        case .reducePayment:
            InfoRow(
                icon: "arrow.down.circle",
                label: String(localized: "loan.paymentReduction", defaultValue: "Payment reduced by"),
                amount: NSDecimalNumber(decimal: loanInfo.monthlyPayment - preview.monthlyPayment).doubleValue,
                currency: account.currency
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            Divider().padding(.leading, AppSpacing.lg)
            InfoRow(
                icon: "banknote",
                label: String(localized: "loan.newMonthlyPayment", defaultValue: "New monthly payment"),
                amount: NSDecimalNumber(decimal: preview.monthlyPayment).doubleValue,
                currency: account.currency
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(String(localized: "button.close"))
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                saveRepayment()
            } label: {
                Image(systemName: "checkmark")
            }
            .primaryButton()
            .disabled(!isFormValid)
            .accessibilityLabel(String(localized: "button.save"))
        }
    }

    // MARK: - Lifecycle

    private func applyDefaults() {
        selectedCurrency = account.currency
        if selectedSourceAccountId == nil, let first = availableAccounts.first {
            selectedSourceAccountId = first.id
        }
        if selectedCategory == nil,
           let candidate = initialCategory,
           candidate != TransactionType.loanPaymentCategoryName,
           availableCategories.contains(candidate) {
            selectedCategory = candidate
            if selectedSubcategoryIds.isEmpty {
                selectedSubcategoryIds = initialSubcategoryIds
            }
        }
    }

    // MARK: - Validation + Save

    private var isFormValid: Bool {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return false }
        guard amount <= loanInfo.remainingPrincipal else { return false }
        return !(selectedSourceAccountId ?? "").isEmpty
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
        guard let sourceId = selectedSourceAccountId, !sourceId.isEmpty else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.noSourceAccount", defaultValue: "Select a source account")
            }
            HapticManager.error()
            return
        }
        validationError = nil

        let dateStr = DateFormatters.dateFormatter.string(from: repaymentDate)
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote = trimmedNote.isEmpty ? nil : trimmedNote
        let result = LoanEarlyRepaymentFormResult(
            amount: amount,
            date: dateStr,
            type: repaymentType,
            sourceAccountId: sourceId,
            note: resolvedNote,
            category: selectedCategory,
            subcategoryIds: selectedSubcategoryIds
        )
        onRepayment(result)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Early Repayment") {
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

    let sourceAccount = Account(
        id: "source-1",
        name: "Kaspi Gold",
        currency: "KZT",
        iconSource: .brandService("kaspi.kz"),
        initialBalance: 500_000
    )

    LoanEarlyRepaymentView(
        account: sampleAccount,
        loanInfo: sampleAccount.loanInfo!,
        availableAccounts: [sourceAccount],
        balanceCoordinator: coordinator.balanceCoordinator,
        baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
        appSettings: coordinator.transactionsViewModel.appSettings,
        onRepayment: { _ in }
    )
    .environment(coordinator)
}
