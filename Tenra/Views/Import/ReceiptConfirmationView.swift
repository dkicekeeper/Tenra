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
//  surface instead: merchant, total, currency, date, with a single action
//  that persists through TransactionsViewModel.addTransaction — the same
//  entry point CSV/voice import already use for account-less, category-less
//  transactions (TransactionStore.validate explicitly allows both nil
//  accountId and an empty category as "uncategorized").
//

import SwiftUI

struct ReceiptConfirmationView: View {
    let draft: ReceiptDraft
    let baseCurrency: String
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel

    @Environment(\.dismiss) private var dismiss

    // Receipt carries its own currency, so the default prefers a regular
    // account already denominated in it over the plain "first regular
    // account" rule voice input uses (voice operations don't have a
    // receipt-scoped currency to match against).
    @State private var selectedAccountId: String?

    init(
        draft: ReceiptDraft,
        baseCurrency: String,
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel
    ) {
        self.draft = draft
        self.baseCurrency = baseCurrency
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel

        let receiptCurrency = draft.currency ?? baseCurrency
        let defaultAccountId = accountsViewModel.regularAccounts
            .first(where: { $0.currency == receiptCurrency })?.id
            ?? accountsViewModel.regularAccounts.first?.id
        _selectedAccountId = State(initialValue: defaultAccountId)
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
                        InfoRow(
                            icon: "storefront",
                            label: String(localized: "import.receipt.merchant"),
                            value: draft.merchant
                        )
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)

                        Divider().padding(.leading, AppSpacing.lg)

                        InfoRow(
                            icon: "banknote",
                            label: String(localized: "import.receipt.total"),
                            amount: draft.total,
                            currency: currency
                        )
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)

                        Divider().padding(.leading, AppSpacing.lg)

                        InfoRow(
                            icon: "calendar",
                            label: String(localized: "import.receipt.date"),
                            value: dateString
                        )
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .screenPadding()

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
    }

    private var addButton: some View {
        Button {
            HapticManager.light()
            guard let selectedAccountId else { return }
            transactionsViewModel.addTransaction(makeTransaction(accountId: selectedAccountId))
            dismiss()
        } label: {
            Text(String(localized: "import.receipt.add"))
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

    private func makeTransaction(accountId: String) -> Transaction {
        Transaction(
            id: "",
            date: dateString,
            description: draft.merchant,
            amount: draft.total,
            currency: currency,
            type: .expense,
            category: "",
            accountId: accountId
        )
    }
}

#Preview {
    let coordinator = AppCoordinator()
    ReceiptConfirmationView(
        draft: ReceiptDraft(merchant: "Green Grocer", total: 4590, currency: "KZT", date: "2026-08-09"),
        baseCurrency: "KZT",
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel
    )
}
