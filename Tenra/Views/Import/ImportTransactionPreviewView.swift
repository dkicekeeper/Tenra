//
//  ImportTransactionPreviewView.swift
//  Tenra
//
//  Final step of the PDF/CSV import flow: review parsed transactions,
//  select which ones to import, assign accounts, and confirm.
//
//  Phase 16 (2026-02-17): Full localization, spring animations, BounceButtonStyle, accessibility
//  Moved from Views/Transactions/ → Views/Import/ (correct domain)
//  Renamed: TransactionPreviewView → ImportTransactionPreviewView
//

import SwiftUI

struct ImportTransactionPreviewView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TransactionStore.self) private var transactionStore
    let transactions: [Transaction]
    let customCategories: [CustomCategory]
    /// transactionId -> suggested category name (CategorySuggestionProvider).
    var suggestedCategories: [String: String] = [:]
    /// transactionId -> why the row looks already present (ImportDuplicateDetector).
    /// Such rows start unchecked but stay selectable.
    var duplicateReasons: [String: ImportDuplicateDetector.Reason] = [:]
    /// transactionId -> cash withdrawal or own-account move (statement operation
    /// column); such rows start unchecked.
    var uncheckedMoves: [String: StatementOperationKind] = [:]
    @Environment(\.dismiss) var dismiss

    @State private var selectedTransactions: Set<String> = Set()
    @State private var accountMapping: [String: String] = [:] // transactionId -> accountId
    @State private var categoryMapping: [String: String] = [:] // transactionId -> category name ("" = uncategorized)
    /// Rows whose category the user picked by hand; same-merchant propagation never overrides them.
    @State private var manuallyCategorized: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Text(String(format: String(localized: "transactionPreview.found"), transactions.count))
                        .font(AppTypography.h4)
                    Text(String(localized: "transactionPreview.selectHint"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .cardContentPadding()
                .frame(maxWidth: .infinity)
                .background(AppColors.bgCard)

                // Transaction list
                List {
                    ForEach(transactions) { transaction in
                        ImportTransactionPreviewRow(
                            transaction: transaction,
                            isSelected: selectedTransactions.contains(transaction.id),
                            selectedAccountId: accountMapping[transaction.id],
                            availableAccounts: availableAccounts(for: transaction),
                            onToggle: {
                                let accounts = availableAccounts(for: transaction)
                                // No account exists in this transaction's currency:
                                // the row must never become selectable, or it would
                                // save with a nil accountId and become invisible to
                                // every balance calculation.
                                guard !accounts.isEmpty else { return }
                                withAnimation(AppAnimation.contentSpring) {
                                    if selectedTransactions.contains(transaction.id) {
                                        selectedTransactions.remove(transaction.id)
                                        accountMapping.removeValue(forKey: transaction.id)
                                    } else {
                                        selectedTransactions.insert(transaction.id)
                                        if let account = accounts.first {
                                            accountMapping[transaction.id] = account.id
                                        }
                                    }
                                }
                            },
                            onAccountSelect: { accountId in
                                accountMapping[transaction.id] = accountId
                            },
                            category: effectiveCategory(for: transaction),
                            categoryOptions: categoryOptions(for: transaction),
                            customCategories: customCategories,
                            duplicateReason: duplicateReasons[transaction.id],
                            uncheckedMove: uncheckedMoves[transaction.id],
                            onCategorySelect: { name in
                                selectCategory(name, for: transaction)
                            }
                        )
                    }
                }
                .listStyle(PlainListStyle())

                // Action buttons — Select All / Deselect All
                HStack(spacing: AppSpacing.md) {
                    Button {
                        withAnimation(AppAnimation.contentSpring) {
                            // Only select rows that have a matching account —
                            // mirrors the per-row guard in onToggle so "Select All"
                            // can never leave a selected row without an account.
                            let selectable = transactions.filter { startsSelected($0) }
                            selectedTransactions = Set(selectable.map { $0.id })
                            for transaction in selectable {
                                if let account = availableAccounts(for: transaction).first {
                                    accountMapping[transaction.id] = account.id
                                }
                            }
                        }
                    } label: {
                        Text("transactionPreview.selectAll")
                            .frame(maxWidth: .infinity)
                            .padding(AppSpacing.md)
                            .background(AppColors.accent.opacity(0.1))
                            .foregroundStyle(AppColors.accent)
                            .clipShape(.rect(cornerRadius: AppRadius.button))
                    }
                    .accessibilityLabel(String(localized: "transactionPreview.selectAll"))

                    Button {
                        withAnimation(AppAnimation.contentSpring) {
                            selectedTransactions.removeAll()
                            accountMapping.removeAll()
                        }
                    } label: {
                        Text("transactionPreview.deselectAll")
                            .frame(maxWidth: .infinity)
                            .padding(AppSpacing.md)
                            .background(AppColors.bgMuted)
                            .foregroundStyle(AppColors.textSecondary)
                            .clipShape(.rect(cornerRadius: AppRadius.button))
                    }
                    .accessibilityLabel(String(localized: "transactionPreview.deselectAll"))
                }
                .cardContentPadding()

                // Add selected button
                Button {
                    addSelectedTransactions()
                } label: {
                    Text(String(format: String(localized: "transactionPreview.addSelected"), selectedTransactions.count))
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(selectedTransactions.isEmpty ? AppColors.bgMuted : AppColors.accent)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: AppRadius.button))
                }
                .buttonStyle(BounceButtonStyle())
                .disabled(selectedTransactions.isEmpty)
                .screenPadding()
                .padding(.bottom, AppSpacing.md)
                .accessibilityLabel(String(format: String(localized: "transactionPreview.addSelected"), selectedTransactions.count))
                .accessibilityAddTraits(selectedTransactions.isEmpty ? .isButton : [.isButton])
            }
            .navigationTitle(String(localized: "navigation.transactionPreview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                categoryMapping = suggestedCategories
                let selectable = transactions.filter { startsSelected($0) }
                selectedTransactions = Set(selectable.map { $0.id })
                for transaction in selectable {
                    if let account = availableAccounts(for: transaction).first {
                        accountMapping[transaction.id] = account.id
                    }
                }
            }
        }
    }

    private func availableAccounts(for transaction: Transaction) -> [Account] {
        Self.availableAccounts(for: transaction, regularAccounts: accountsViewModel.regularAccounts)
    }

    /// Rows checked by default (and by "Select All"): importable, not already in
    /// Tenra, and not a cash withdrawal or own-account move.
    private func startsSelected(_ transaction: Transaction) -> Bool {
        !availableAccounts(for: transaction).isEmpty
            && duplicateReasons[transaction.id] == nil
            && uncheckedMoves[transaction.id] == nil
    }

    // MARK: - Categories

    private static func isCategorizable(_ transaction: Transaction) -> Bool {
        transaction.type == .expense || transaction.type == .income
    }

    /// The category shown and saved for a row: the user's choice or the
    /// suggestion for income/expense rows; transfers keep their technical category.
    private func effectiveCategory(for transaction: Transaction) -> String {
        guard Self.isCategorizable(transaction) else { return transaction.category }
        return categoryMapping[transaction.id] ?? transaction.category
    }

    private func categoryOptions(for transaction: Transaction) -> [String] {
        customCategories
            .filter { $0.type == transaction.type }
            .sortedByOrder()
            .map(\.name)
    }

    /// `TransactionStore.validate` rejects a non-empty category the user does
    /// not have, and `addSelectedTransactions` would then drop the row silently.
    /// Anything that is not one of the user's categories saves as uncategorized.
    private func savableCategory(for transaction: Transaction) -> String {
        let category = effectiveCategory(for: transaction)
        guard Self.isCategorizable(transaction), !category.isEmpty else { return category }
        let known = customCategories.contains { $0.type == transaction.type && $0.name == category }
        return known ? category : ""
    }

    /// Sets the row's category and carries it to the other rows of the same
    /// merchant and type in this import, except rows the user already set by hand.
    private func selectCategory(_ name: String, for transaction: Transaction) {
        let merchant = CategorySuggestionService.normalizedMerchant(transaction.description)
        withAnimation(AppAnimation.contentSpring) {
            categoryMapping[transaction.id] = name
            manuallyCategorized.insert(transaction.id)
            guard merchant.count >= CategorySuggestionService.minimumMerchantLength else { return }
            for other in transactions
            where other.id != transaction.id
                && other.type == transaction.type
                && !manuallyCategorized.contains(other.id)
                && CategorySuggestionService.normalizedMerchant(other.description) == merchant {
                categoryMapping[other.id] = name
            }
        }
    }

    /// Pure account-matching rule, factored out so it is unit-testable without
    /// standing up a View or an AccountsViewModel.
    ///
    /// Callers MUST pass `regularAccounts`, never `accounts` (Fix 5): assigning
    /// a plain income/expense transaction to a deposit or loan account would
    /// move its derived balance directly, bypassing DepositInterestService's
    /// principal/interest bookkeeping and LoanPaymentService's leg accounting.
    /// Every other transaction-entry surface (ReceiptConfirmationView,
    /// VoiceInputConfirmationView, TransactionAddCoordinator, SubscriptionEditView)
    /// uses `regularAccounts` for the same reason.
    ///
    /// An empty result (Fix 4) means the row must not be selectable: a
    /// transaction saved with a nil accountId is invisible to every balance
    /// calculation, since accountId drives balance derivation throughout
    /// this codebase.
    static func availableAccounts(for transaction: Transaction, regularAccounts: [Account]) -> [Account] {
        regularAccounts.filter { $0.currency == transaction.currency }
    }

    private func addSelectedTransactions() {
        let transactionsToAdd = transactions.filter { selectedTransactions.contains($0.id) }

        Task {
            var saved: [Transaction] = []
            for transaction in transactionsToAdd {
                // A row can only be selected when availableAccounts(for:) is
                // non-empty (see onToggle/onAppear/Select All above), but this
                // guard is the last line of defense: nothing with a nil
                // accountId may reach transactionStore.add regardless of UI
                // state, since accountId drives every balance calculation.
                guard let accountId = accountMapping[transaction.id] else { continue }
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: savableCategory(for: transaction),
                    subcategory: transaction.subcategory,
                    accountId: accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: transaction.recurringSeriesId,
                    recurringOccurrenceId: transaction.recurringOccurrenceId,
                    createdAt: transaction.createdAt
                )

                do {
                    saved.append(try await transactionStore.add(updatedTransaction))
                } catch {
                }
            }

            // Rows that predate an account are already in the balance the user
            // entered when creating it; keep that balance instead of double-counting.
            if let coordinator = accountsViewModel.balanceCoordinator {
                await ImportBalanceCompensation.apply(saved: saved, store: transactionStore, coordinator: coordinator)
            }

            RatingPromptService.shared.recordTransactionAdded(count: saved.count)
            dismiss()
        }
    }
}

// MARK: - ImportTransactionPreviewRow

struct ImportTransactionPreviewRow: View {
    let transaction: Transaction
    let isSelected: Bool
    let selectedAccountId: String?
    let availableAccounts: [Account]
    let onToggle: () -> Void
    let onAccountSelect: (String) -> Void
    /// Effective category for this row (suggested or picked; "" = uncategorized).
    let category: String
    let categoryOptions: [String]
    let customCategories: [CustomCategory]
    /// Set when the row looks already present; the row starts unchecked.
    let duplicateReason: ImportDuplicateDetector.Reason?
    /// Cash withdrawal or own-account move; the row starts unchecked.
    let uncheckedMove: StatementOperationKind?
    let onCategorySelect: (String) -> Void

    private var isCategorizable: Bool {
        transaction.type == .expense || transaction.type == .income
    }

    // Resolved against the user's real categories, so a suggested category
    // shows its own icon and colour on the card.
    private var styleData: CategoryStyleData {
        CategoryStyleHelper.cached(category: category, type: transaction.type, customCategories: customCategories)
    }

    /// The card renders the row as it will be saved, i.e. with the effective category.
    private var displayTransaction: Transaction {
        Transaction(
            id: transaction.id,
            date: transaction.date,
            description: transaction.description,
            amount: transaction.amount,
            currency: transaction.currency,
            convertedAmount: transaction.convertedAmount,
            type: transaction.type,
            category: category,
            subcategory: transaction.subcategory,
            accountId: transaction.accountId,
            targetAccountId: transaction.targetAccountId,
            accountName: transaction.accountName,
            targetAccountName: transaction.targetAccountName,
            targetCurrency: transaction.targetCurrency,
            targetAmount: transaction.targetAmount,
            recurringSeriesId: transaction.recurringSeriesId,
            recurringOccurrenceId: transaction.recurringOccurrenceId,
            createdAt: transaction.createdAt
        )
    }

    /// Picker options; keeps a current value that is not in the list (should not
    /// happen) selectable, so the Picker never holds an unmatched selection.
    private var pickerCategories: [String] {
        guard !category.isEmpty, !categoryOptions.contains(category) else { return categoryOptions }
        return categoryOptions + [category]
    }

    /// No regular account exists in this transaction's currency. The row
    /// must stay unselectable (Fix 4): saving with a nil accountId makes the
    /// transaction invisible to every balance calculation, since accountId
    /// drives balance derivation throughout this codebase.
    private var hasNoMatchingAccount: Bool { availableAccounts.isEmpty }

    private func duplicateLabel(for reason: ImportDuplicateDetector.Reason) -> String {
        switch reason {
        case .alreadyAdded:
            return String(localized: "transactionPreview.possibleDuplicate")
        case .subscriptionOccurrence:
            return String(localized: "transactionPreview.coveredBySubscription")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                // Checkbox button with spring animation
                Button(action: onToggle) {
                    Image(systemName: hasNoMatchingAccount
                        ? "exclamationmark.circle"
                        : (isSelected ? "checkmark.circle.fill" : "circle")
                    )
                        .foregroundStyle(hasNoMatchingAccount
                            ? AppColors.warning
                            : (isSelected ? AppColors.accent : AppColors.textSecondary)
                        )
                        .font(AppTypography.h4)
                        .animation(AppAnimation.contentSpring, value: isSelected)
                }
                .buttonStyle(.plain)
                .disabled(hasNoMatchingAccount)
                .accessibilityLabel(hasNoMatchingAccount
                    ? String(localized: "transactionPreview.noMatchingAccount")
                    : (isSelected
                        ? String(localized: "button.select")
                        : String(localized: "transactionPreview.selectHint"))
                )
                .accessibilityAddTraits(.isButton)

                // Pure, side-effect-free card (per TransactionCard.swift's own
                // header: "For read-only / selection UIs use TransactionCardView
                // directly — it has no env dependencies and no side effects").
                // These transactions do not exist in TransactionStore yet, so
                // TransactionCard's tap-to-edit / swipe-to-delete / recurring
                // actions would resolve against a transaction the store has
                // never seen — this screen's own checkbox and account picker
                // are the only actions that make sense before import.
                TransactionCardView(
                    transaction: displayTransaction,
                    currency: transaction.currency,
                    styleData: styleData
                )
            }

            // No account in this currency: tell the user why the row cannot
            // be imported rather than letting it disappear silently.
            if hasNoMatchingAccount {
                Text(String(localized: "transactionPreview.noMatchingAccount"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
                    .padding(.leading, AppSpacing.xl)
            }

            // Already in Tenra (re-imported row, or a charge a subscription series
            // already generated): say why the row starts unchecked.
            if let duplicateReason {
                Text(duplicateLabel(for: duplicateReason))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
                    .padding(.leading, AppSpacing.xl)
            } else if let uncheckedMove {
                Text(uncheckedMove == .cashWithdrawal
                     ? String(localized: "transactionPreview.cashWithdrawal")
                     : String(localized: "transactionPreview.ownAccountTransfer"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.leading, AppSpacing.xl)
            }

            // Account selector (visible only when selected)
            if isSelected && !availableAccounts.isEmpty {
                Picker(String(localized: "transactionPreview.account"), selection: Binding(
                    get: { selectedAccountId ?? "" },
                    set: { onAccountSelect($0) }
                )) {
                    Text("transactionPreview.noAccount").tag("")
                    ForEach(availableAccounts) { account in
                        Text("\(account.name) (\(Formatting.currencySymbol(for: account.currency)))").tag(account.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, AppSpacing.xl)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Category selector (income/expense rows, visible only when selected)
            if isSelected && isCategorizable {
                Picker(String(localized: "transaction.category"), selection: Binding(
                    get: { category },
                    set: { onCategorySelect($0) }
                )) {
                    Text(String(localized: "category.uncategorized")).tag("")
                    ForEach(pickerCategories, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, AppSpacing.xl)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Preview

#Preview("Empty") {
    let coordinator = AppCoordinator()
    ImportTransactionPreviewView(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactions: [],
        customCategories: coordinator.categoriesViewModel.customCategories
    )
    .environment(coordinator.transactionStore)
}

#Preview("With Transactions") {
    let coordinator = AppCoordinator()
    let mockAccountId = "acc-kaspi"
    let sampleTransactions: [Transaction] = [
        Transaction(
            id: "prev-1",
            date: DateFormatters.dateFormatter.string(from: Date()),
            description: "Supermarket",
            amount: 8500,
            currency: "KZT",
            type: .expense,
            category: "Food",
            accountId: mockAccountId
        ),
        Transaction(
            id: "prev-2",
            date: DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(-86400)),
            description: "Зарплата",
            amount: 450000,
            currency: "KZT",
            type: .income,
            category: "Salary",
            accountId: mockAccountId
        ),
        Transaction(
            id: "prev-3",
            date: DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(-172800)),
            description: "Netflix",
            amount: 4990,
            currency: "KZT",
            type: .expense,
            category: "Subscriptions",
            accountId: mockAccountId
        )
    ]

    ImportTransactionPreviewView(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactions: sampleTransactions,
        customCategories: coordinator.categoriesViewModel.customCategories
    )
    .environment(coordinator.transactionStore)
}
