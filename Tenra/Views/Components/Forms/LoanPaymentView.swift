//
//  LoanPaymentView.swift
//  Tenra
//
//  Manual loan-payment composer. Mirrors the TransactionEditView layout
//  (Hero → Amount → Source → Category → Subcategory → Note → Impact) so users
//  see one consistent transaction form whether they're editing an existing tx
//  or creating a new loan payment.
//

import SwiftUI

/// Outcome of `LoanPaymentView` collected on save and forwarded to the caller for
/// persistence. Bundling the fields into a struct keeps the closure signature
/// readable as the form grows (amount + date + source + note + category + subcategories).
struct LoanPaymentFormResult {
    let amount: Decimal
    let date: String
    let sourceAccountId: String
    let note: String?
    /// `nil` means "keep the technical default" (e.g. `Loan Payment` for new payments).
    /// Non-nil values come from the expense catalog and tag the payment alongside
    /// regular spending.
    let category: String?
    let subcategoryIds: Set<String>
}

struct LoanPaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let availableAccounts: [Account]
    let balanceCoordinator: BalanceCoordinator
    let baseCurrency: String
    let appSettings: AppSettings
    /// Optional: amount of the most recent linked loan-payment for this loan, used as
    /// the default value in the amount field. If `nil`, falls back to `loanInfo.monthlyPayment`.
    var lastPaidAmount: Decimal? = nil
    /// Expense-catalog categories the user can assign to this payment. When empty
    /// the picker is hidden and `category` defaults to the technical
    /// `Loan Payment` constant.
    var availableCategories: [String] = []
    var customCategories: [CustomCategory] = []
    var categoriesViewModel: CategoriesViewModel? = nil
    /// Pre-selected category (e.g. the one used for the previous payment of this loan,
    /// falling back to `LoanInfo.defaultCategory`).
    var initialCategory: String? = nil
    /// Pre-selected subcategory ids — same precedence as `initialCategory`.
    var initialSubcategoryIds: Set<String> = []
    let onPayment: (LoanPaymentFormResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var calc = CalculatorInputModel()
    @FocusState private var descriptionFocused: Bool
    @State private var selectedCurrency: String = ""
    @State private var paymentDate: Date = Date()
    @State private var selectedSourceAccountId: String? = nil
    @State private var noteText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var showingSubcategorySearch: Bool = false
    @State private var subcategorySearchText: String = ""

    @State private var validationError: String? = nil

    /// Resolves the custom-category id for the currently selected category — needed
    /// to feed `SubcategorySelectorView`.
    private var selectedCategoryId: String? {
        guard let name = selectedCategory else { return nil }
        return customCategories.first { $0.name == name }?.id
    }

    /// Localised hero title — same key the rest of the app uses for `.loanPayment`
    /// transactions, so the create flow and the edit flow read identically.
    private var heroTitle: String {
        String(localized: "transaction.type.loanPayment", defaultValue: "Платёж по кредиту")
    }

    /// Hero icon: prefer the loan account's brand logo (e.g. `halykbank.kz`),
    /// fall back to a generic `creditcard.fill` SF Symbol when none is set.
    private var heroIcon: IconSource {
        account.iconSource ?? .sfSymbol("creditcard.fill")
    }

    /// Subtitle shown under the hero: scheduled monthly payment as reference so
    /// the user can compare what the formula expects vs what they're entering.
    private var heroSubtitle: String {
        let scheduled = Formatting.formatCurrencySmart(
            NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue,
            currency: account.currency
        )
        return String(
            format: String(localized: "loan.scheduledPayment", defaultValue: "Scheduled: %@"),
            scheduled
        )
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
                            .screenPadding()
                    }

                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $selectedCurrency,
                        errorMessage: nil,
                        baseCurrency: baseCurrency,
                        accountCurrencies: Set([account.currency]),
                        appSettings: appSettings,
                        calculatorModel: calc,
                        onCalculatorTap: { descriptionFocused = false }
                    )

                    fromSection
                    categorySection
                    subcategorySection
                    noteSection
                    impactSection
                }
                .animation(AppAnimation.gentleSpring, value: validationError)
                .animation(AppAnimation.gentleSpring, value: selectedCategory)
                .animation(AppAnimation.gentleSpring, value: amountText)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .dateButtonsSafeArea(selectedDate: $paymentDate, isDisabled: !isFormValid, maxDate: Date()) { _ in
                savePayment()
            }
            .safeAreaInset(edge: .bottom) {
                if !descriptionFocused {
                    CalculatorKeypad(model: calc)
                        .background(AppColors.bgBase)
                }
            }
            .onChange(of: calc.amountText) { _, newValue in
                amountText = newValue
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
                .screenPadding()

            AccountSelectorView(
                accounts: availableAccounts,
                selectedAccountId: $selectedSourceAccountId,
                emptyStateMessage: String(localized: "loan.noSourceAccounts", defaultValue: "No accounts"),
                balanceCoordinator: balanceCoordinator
            )
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
        // Show the section unconditionally when subcategory tagging is available
        // for this loan (i.e. there's an expense catalog the user can tag against).
        // Without an explicit header users can miss the picker — it only renders
        // *after* a category is picked, which fails the "what fields can I fill"
        // discoverability test.
        if let categoriesVM = categoriesViewModel, !availableCategories.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SectionHeaderView(String(localized: "loan.subcategoryHeader", defaultValue: "Subcategory"))
                    .screenPadding()

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
                    .screenPadding()
                }
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        FormTextField(
            text: $noteText,
            placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
            style: .multiline(min: 2, max: 6),
            externalFocus: $descriptionFocused
        )
        .screenPadding()
    }

    @ViewBuilder
    private var impactSection: some View {
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
                    amount: NSDecimalNumber(decimal: breakdown.interest).doubleValue,
                    currency: account.currency
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                Divider().padding(.leading, AppSpacing.lg)
                InfoRow(
                    icon: "arrow.down.to.line",
                    label: String(localized: "loan.principalPortion", defaultValue: "Principal"),
                    amount: NSDecimalNumber(decimal: breakdown.principal).doubleValue,
                    currency: account.currency
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
            }
            .screenPadding()
        }
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
                savePayment()
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
        // Default to the most recently paid amount if available — users typically
        // round their actual payment (e.g. 340 000) above the calculated annuity
        // (e.g. 336 829) and the prior actual is the better suggestion.
        let defaultAmount = lastPaidAmount ?? loanInfo.monthlyPayment
        amountText = AmountInputFormatting.bindingString(for: defaultAmount)
        calc.seed(amountText)
        selectedCurrency = account.currency
        if selectedSourceAccountId == nil, let first = availableAccounts.first {
            selectedSourceAccountId = first.id
        }
        if selectedCategory == nil,
           let candidate = initialCategory,
           candidate != TransactionType.loanPaymentCategoryName,
           availableCategories.contains(candidate) {
            selectedCategory = candidate
            // Subcategory ids are scoped to a category — only seed them when
            // the parent category was successfully pre-selected, otherwise the
            // ids would refer to a category that's not visible in the picker.
            if selectedSubcategoryIds.isEmpty {
                selectedSubcategoryIds = initialSubcategoryIds
            }
        }
    }

    // MARK: - Validation + Save

    private var isFormValid: Bool {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return false }
        return !(selectedSourceAccountId ?? "").isEmpty
    }

    private func savePayment() {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidAmount", defaultValue: "Enter a valid amount")
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

        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote = trimmedNote.isEmpty ? nil : trimmedNote
        let result = LoanPaymentFormResult(
            amount: amount,
            date: dateStr,
            sourceAccountId: sourceId,
            note: resolvedNote,
            category: selectedCategory,
            subcategoryIds: selectedSubcategoryIds
        )
        onPayment(result)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Loan Payment") {
    let coordinator = AppCoordinator()
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
        iconSource: .brandService("kaspi.kz"),
        initialBalance: 500_000
    )

    LoanPaymentView(
        account: sampleLoanAccount,
        loanInfo: sampleLoanAccount.loanInfo!,
        availableAccounts: [sourceAccount],
        balanceCoordinator: coordinator.balanceCoordinator,
        baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
        appSettings: coordinator.transactionsViewModel.appSettings,
        onPayment: { _ in }
    )
    .environment(coordinator)
}
