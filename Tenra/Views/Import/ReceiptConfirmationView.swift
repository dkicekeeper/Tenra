//
//  ReceiptConfirmationView.swift
//  Tenra
//
//  Confirmation sheet for a receipt scanned via the camera.
//
//  TransactionEditView (Views/Transactions/TransactionEditView.swift) is
//  edit-only: it requires an already-existing Transaction plus
//  AccountsViewModel, TransactionStore, accounts, customCategories, and a
//  BalanceCoordinator — none of which PDFImportCoordinator holds, and its
//  save path (TransactionEditCoordinator.save) unconditionally calls
//  transactionStore.update, never .add. There is no "add transaction with
//  prefill" seam to reuse without redesigning that view's initializer, which
//  is out of scope here. This is a minimal, purpose-built confirmation
//  surface instead: merchant, total, currency, date, a category (pre-filled
//  by CategorySuggestionProvider from the merchant name, optional), with a
//  single action that persists through TransactionsViewModel.addTransaction.
//  TransactionStore.validate still accepts an empty category as
//  "uncategorized" when the user leaves it unset.
//
//  A receipt a bank app shared names the person the money went to: when the user owes that
//  person (an open "I owe" debt, DebtRecipientMatcher), a switch records the payment as the
//  debt's repayment too, in the debt's currency and at most what is left of it, once the
//  expense is saved (docs/plan-auto-capture.md §6). The switch is on when the name came from
//  the receipt's recipient label, off when it is only the receipt's top line.
//

import SwiftUI

struct ReceiptConfirmationView: View {
    let draft: ReceiptDraft
    let baseCurrency: String
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator

    // Receipt carries its own currency, so the default prefers a regular
    // account already denominated in it over the plain "first regular
    // account" rule voice input uses (voice operations don't have a
    // receipt-scoped currency to match against).
    @State private var selectedAccountId: String?

    /// Pre-filled from CategorySuggestionProvider; nil saves as uncategorized.
    @State private var selectedCategoryName: String?

    /// Record the payment as the repayment of the debt the recipient matches.
    @State private var recordsRepayment: Bool

    init(
        draft: ReceiptDraft,
        baseCurrency: String,
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) {
        self.draft = draft
        self.baseCurrency = baseCurrency
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel

        let receiptCurrency = draft.currency ?? baseCurrency
        let defaultAccountId = accountsViewModel.regularAccounts
            .first(where: { $0.currency == receiptCurrency })?.id
            ?? accountsViewModel.regularAccounts.first?.id
        _selectedAccountId = State(initialValue: defaultAccountId)
        _recordsRepayment = State(initialValue: draft.isRecipient)
    }

    private var currency: String { draft.currency ?? baseCurrency }
    private var dateString: String {
        draft.date ?? DateFormatters.dateFormatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(header: String(localized: "import.receipt.detailsHeader")) {
                        UniversalRow(
                            String(localized: "import.receipt.merchant"),
                            icon: "storefront",
                            accessory: .info(draft.merchant)
                        )

                        UniversalRow(
                            String(localized: "import.receipt.total"),
                            icon: "banknote",
                            accessory: .amount(draft.total, currency: currency)
                        )

                        UniversalRow(
                            String(localized: "transaction.date"),
                            icon: "calendar",
                            accessory: .info(dateString)
                        )
                    }
                    .screenPadding()

                    CategorySelectorView(
                        categories: categoriesViewModel.customCategories
                            .filter { $0.type == .expense }
                            .sortedByOrder()
                            .map { $0.name },
                        type: .expense,
                        customCategories: categoriesViewModel.customCategories,
                        selectedCategory: $selectedCategoryName,
                        emptyStateMessage: String(localized: "transactionForm.noCategories")
                    )

                    if let repayment = debtRepayment {
                        FormSection(footer: String(format: String(localized: "import.receipt.debtRepayment.footer"), repayment.debt.person)) {
                            UniversalRow(
                                String(localized: "import.receipt.debtRepayment"),
                                icon: "arrow.uturn.backward.circle",
                                accessory: .toggle($recordsRepayment)
                            )
                        }
                        .screenPadding()
                    }

                    if let balanceCoordinator = accountsViewModel.balanceCoordinator {
                        AccountSelectorView(
                            accounts: accountsViewModel.regularAccounts,
                            selectedAccountId: $selectedAccountId,
                            emptyStateMessage: String(localized: "voiceConfirmation.noAccounts"),
                            balanceCoordinator: balanceCoordinator
                        )
                        .screenPadding()
                    }

                    addButton
                }
                .padding(.top, AppSpacing.lg)
            }
            .task { await suggestCategory() }
            .navigationTitle(String(localized: "import.receipt.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "button.cancel"))
                }
            }
        }
        .softScrollEdges()
    }

    private var addButton: some View {
        Button {
            HapticManager.light()
            guard let selectedAccountId else { return }
            let transaction = makeTransaction(accountId: selectedAccountId)
            let viewModel = transactionsViewModel
            let debts = coordinator.debtStore
            var repayment: (debtId: String, entry: DebtRepayment)?
            if recordsRepayment, let match = debtRepayment {
                repayment = (match.debt.id, DebtRepayment(
                    amount: match.amount,
                    date: FastDateParser.date(from: dateString) ?? Date(),
                    note: draft.merchant
                ))
            }
            // The repayment follows the expense: a failed save repays nothing.
            Task { [repayment] in
                guard await viewModel.addTransactionAndWait(transaction) != nil, let repayment else { return }
                await debts.addRepayment(repayment.entry, to: repayment.debtId)
            }
            dismiss()
        } label: {
            Text(String(localized: "button.add"))
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.accent)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: AppRadius.button))
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(selectedAccountId == nil)
        .opacity(selectedAccountId == nil ? 0.5 : 1)
        .screenPadding()
    }

    /// The open debt the recipient matches and the payment in its currency, at most what is
    /// left of the debt; nil without one, or without a rate to convert to it.
    private var debtRepayment: (debt: PersonalDebt, amount: Double)? {
        guard let debt = DebtRecipientMatcher.debt(repaidTo: draft.merchant, in: coordinator.debtStore.debts),
              debt.remaining > 0 else {
            return nil
        }
        guard let amount = CurrencyConverter.convertSync(amount: draft.total, from: currency, to: debt.currency) else {
            return nil
        }
        return (debt, min(amount, debt.remaining))
    }

    private func makeTransaction(accountId: String) -> Transaction {
        Transaction(
            id: "",
            date: dateString,
            description: draft.merchant,
            amount: draft.total,
            currency: currency,
            type: .expense,
            category: selectedCategoryName ?? "",
            accountId: accountId
        )
    }

    /// Receipts carry no category; suggest one from the merchant name. Never
    /// overwrites a category the user picked while the suggestion was computing.
    private func suggestCategory() async {
        guard selectedCategoryName == nil else { return }
        let probeId = "receipt-probe"
        let probe = Transaction(
            id: probeId,
            date: dateString,
            description: draft.merchant,
            amount: draft.total,
            currency: currency,
            type: .expense,
            category: ""
        )
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel
        )
        let suggestions = await CategorySuggestionProvider.suggestions(
            for: [probe],
            history: transactionsViewModel.transactionStore?.transactions ?? [],
            categories: categoriesViewModel.customCategories,
            keywordMatcher: { parser.keywordCategory(in: $0) }
        )
        if selectedCategoryName == nil, let suggested = suggestions[probeId] {
            selectedCategoryName = suggested
            return
        }
        // Nothing learned or known about this merchant: ask the on-device model.
        let expenseCategories = categoriesViewModel.customCategories
            .filter { $0.type == .expense }
            .sortedByOrder()
            .map(\.name)
        try? await IntelligentCategorySuggester.suggest(
            items: [IntelligentCategorySuggester.Item(id: probeId, description: draft.merchant, type: .expense)],
            categories: [.expense: expenseCategories]
        ) { assigned in
            if selectedCategoryName == nil, let suggested = assigned[probeId] {
                selectedCategoryName = suggested
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    ReceiptConfirmationView(
        draft: ReceiptDraft(merchant: "Green Grocer", total: 4590, currency: "KZT", date: "2026-08-09"),
        baseCurrency: "KZT",
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel
    )
    .environment(coordinator)
}
