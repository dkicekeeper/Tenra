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
//  2026-09-25: the statement's account is chosen once for all rows; rows can be
//  marked as a transfer to/from another own account (learned from saved transfers,
//  or matched to the other side already in Tenra); subcategories are picked and
//  learned. Saving goes through ImportCommitPlanner / ImportCommitter.
//

import SwiftUI

struct ImportTransactionPreviewView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TransactionStore.self) private var transactionStore
    let transactions: [Transaction]
    let customCategories: [CustomCategory]
    /// Writes subcategory links on save. Nil only in previews.
    var categoriesViewModel: CategoriesViewModel? = nil
    /// transactionId -> suggested category name (CategorySuggestionProvider).
    var suggestedCategories: [String: String] = [:]
    /// Subcategories the user linked before, per merchant and category.
    var subcategoryHistory = CategorySuggestionService.SubcategoryIndex()
    /// Transfers between own accounts the user saved before, per account and merchant.
    var transferHistory = ImportTransferHistory.Index()
    /// transactionId -> cash withdrawal or own-account move (statement operation
    /// column); such rows start unchecked unless their transfer account is known.
    var uncheckedMoves: [String: StatementOperationKind] = [:]
    /// Rows whose operation can be a transfer (not a purchase or cash withdrawal);
    /// only these are matched against the other side of a transfer.
    var transferEligibleIds: Set<String> = []
    /// The account the statement belongs to (StatementBankDetector), when known.
    var defaultStatementAccountId: String? = nil
    @Environment(\.dismiss) var dismiss

    @State private var statementAccountId = ""
    @State private var selectedTransactions: Set<String> = Set()
    @State private var accountMapping: [String: String] = [:] // transactionId -> accountId
    @State private var categoryMapping: [String: String] = [:] // transactionId -> category name ("" = uncategorized)
    /// Rows whose category the user picked by hand; same-merchant propagation never overrides them.
    @State private var manuallyCategorized: Set<String> = []
    /// transactionId -> subcategory id (absent = none).
    @State private var subcategoryMapping: [String: String] = [:]
    @State private var manuallySubcategorized: Set<String> = []
    /// transactionId -> the user's other account, when the row is a transfer between own accounts.
    @State private var transferMapping: [String: String] = [:]
    /// transactionId -> why the row looks already present (ImportDuplicateDetector).
    @State private var duplicateReasons: [String: ImportDuplicateDetector.Reason] = [:]
    @State private var transferMatches: [String: ImportTransferMatcher.Match] = [:]
    @State private var isSaving = false

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
                    if !regularAccounts.isEmpty {
                        HStack(spacing: AppSpacing.xs) {
                            Text(String(localized: "transactionPreview.statementAccount"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textSecondary)
                            Picker(String(localized: "transactionPreview.statementAccount"), selection: $statementAccountId) {
                                ForEach(regularAccounts) { account in
                                    Text("\(account.name) (\(Formatting.currencySymbol(for: account.currency)))").tag(account.id)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
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
                            onToggle: { toggle(transaction) },
                            onAccountSelect: { accountId in
                                selectAccount(accountId, for: transaction)
                            },
                            category: effectiveCategory(for: transaction),
                            categoryOptions: categoryOptions(for: transaction),
                            customCategories: customCategories,
                            subcategory: subcategoryMapping[transaction.id].flatMap { transactionStore.subcategoryById[$0] },
                            subcategoryOptions: subcategoryOptions(for: transaction),
                            transferAccount: transferMapping[transaction.id].flatMap { id in
                                regularAccounts.first { $0.id == id }
                            },
                            transferOptions: transferOptions(for: transaction),
                            notice: notice(for: transaction),
                            onCategorySelect: { name in
                                selectCategory(name, for: transaction)
                            },
                            onSubcategorySelect: { id in
                                selectSubcategory(id, for: transaction)
                            },
                            onTransferSelect: { id in
                                selectTransfer(id, for: transaction)
                            }
                        )
                    }
                }
                .listStyle(PlainListStyle())

                // Action buttons — Select All / Deselect All
                HStack(spacing: AppSpacing.md) {
                    Button {
                        withAnimation(AppAnimation.contentSpring) {
                            // Only rows that start selected: importable, not already in
                            // Tenra, not an unresolved cash/own-account move.
                            selectedTransactions = Set(transactions.filter { startsSelected($0) }.map(\.id))
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
                .disabled(selectedTransactions.isEmpty || isSaving)
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
                for transaction in transactions {
                    refreshSubcategory(for: transaction)
                }
            }
            // Accounts, duplicates, transfer matches and the default selection all
            // depend on the statement's account; re-run when the user changes it.
            .task(id: statementAccountId) {
                await analyze()
            }
        }
    }

    private var regularAccounts: [Account] { accountsViewModel.regularAccounts }

    private func availableAccounts(for transaction: Transaction) -> [Account] {
        Self.availableAccounts(for: transaction, regularAccounts: regularAccounts)
    }

    /// The statement's account when it holds this row's currency, otherwise the
    /// first account in that currency (a multi-currency card's USD rows).
    private func defaultAccount(for transaction: Transaction) -> Account? {
        let accounts = availableAccounts(for: transaction)
        return accounts.first { $0.id == statementAccountId } ?? accounts.first
    }

    /// The detected bank's account, else the first account in the currency most
    /// rows use.
    private func initialStatementAccountId() -> String {
        if let id = defaultStatementAccountId, regularAccounts.contains(where: { $0.id == id }) {
            return id
        }
        let counts = Dictionary(grouping: transactions, by: \.currency).mapValues(\.count)
        let mainCurrency = counts.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }?.key
        return (regularAccounts.first { $0.currency == mainCurrency } ?? regularAccounts.first)?.id ?? ""
    }

    /// Rows checked by default (and by "Select All"): importable, not already in
    /// Tenra, and not a cash withdrawal or own-account move whose other account is
    /// unknown. A row with a transfer account is safe to import: it moves money
    /// between two accounts instead of counting as spending or income.
    private func startsSelected(_ transaction: Transaction) -> Bool {
        guard accountMapping[transaction.id] != nil,
              duplicateReasons[transaction.id] == nil else { return false }
        if case .alreadyTransfer = transferMatches[transaction.id] { return false }
        if transferMapping[transaction.id] != nil { return true }
        return uncheckedMoves[transaction.id] == nil
    }

    /// Why the row is flagged, naming the saved transaction it matched so the user
    /// can tell a real duplicate from a coincidence without leaving the screen.
    private func notice(for transaction: Transaction) -> ImportRowNotice? {
        if let reason = duplicateReasons[transaction.id] {
            let record = matchedRecord(reason.existingId)
            switch reason {
            case .alreadyAdded: return .alreadyAdded(record)
            case .subscriptionOccurrence: return .subscription(record)
            case .loanPayment: return .loanPayment(record)
            }
        }
        if case .alreadyTransfer(let existingId) = transferMatches[transaction.id] {
            return .alreadyTransfer(transferRecord(existingId))
        }
        if case .counterpart(let existingId, let accountId) = transferMatches[transaction.id],
           transferMapping[transaction.id] == accountId,
           let account = regularAccounts.first(where: { $0.id == accountId }) {
            return .merge(accountName: account.name, record: matchedRecord(existingId))
        }
        guard transferMapping[transaction.id] == nil, let move = uncheckedMoves[transaction.id] else { return nil }
        return move == .cashWithdrawal ? .cashWithdrawal : .ownAccountMove
    }

    /// A saved entry as a hint names it: its description (or its category when it
    /// has none, as manual entries often do), shortened, and its date.
    private func matchedRecord(_ id: String) -> ImportMatchedRecord? {
        guard let saved = transactionStore.transactionById[id] else { return nil }
        let description = saved.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = description.isEmpty ? saved.category : description
        guard !label.isEmpty else { return nil }
        return ImportMatchedRecord(
            label: label.count > 32 ? String(label.prefix(30)) + "…" : label,
            date: DateFormatters.displayString(from: saved.date)
        )
    }

    private func transferRecord(_ id: String) -> ImportTransferRecord? {
        guard let saved = transactionStore.transactionById[id],
              let from = transactionStore.accounts.first(where: { $0.id == saved.accountId })?.name,
              let to = transactionStore.accounts.first(where: { $0.id == saved.targetAccountId })?.name
        else { return nil }
        return ImportTransferRecord(from: from, to: to, date: DateFormatters.displayString(from: saved.date))
    }

    // MARK: - Selection and accounts

    private func toggle(_ transaction: Transaction) {
        // No account exists in this transaction's currency: the row must never
        // become selectable, or it would save with a nil accountId and become
        // invisible to every balance calculation.
        guard let account = defaultAccount(for: transaction) else { return }
        withAnimation(AppAnimation.contentSpring) {
            if selectedTransactions.contains(transaction.id) {
                selectedTransactions.remove(transaction.id)
            } else {
                selectedTransactions.insert(transaction.id)
                if accountMapping[transaction.id] == nil {
                    accountMapping[transaction.id] = account.id
                }
            }
        }
    }

    private func selectAccount(_ accountId: String, for transaction: Transaction) {
        accountMapping[transaction.id] = accountId
        if transferMapping[transaction.id] == accountId {
            transferMapping.removeValue(forKey: transaction.id)
        }
    }

    /// Accounts, duplicates, transfer matches, learned transfers and the default
    /// selection for the current statement account.
    private func analyze() async {
        guard !statementAccountId.isEmpty else {
            // First run: pick the statement's account; the id change re-runs this task.
            let initial = initialStatementAccountId()
            if !initial.isEmpty { statementAccountId = initial }
            return
        }

        var mapping: [String: String] = [:]
        for transaction in transactions {
            if let account = defaultAccount(for: transaction) { mapping[transaction.id] = account.id }
        }
        accountMapping = mapping

        let rows = transactions
        let existing = transactionStore.transactions
        let eligible = transferEligibleIds
        let ownAccountIds = Set(regularAccounts.map(\.id))
        let (duplicates, matches) = await Task.detached(priority: .userInitiated) {
            let duplicates = ImportDuplicateDetector.detect(
                imported: rows, importedAccounts: mapping, existing: existing
            )
            let matches = ImportTransferMatcher.detect(
                imported: rows,
                importedAccounts: mapping,
                eligibleRowIds: eligible.subtracting(duplicates.keys),
                ownAccountIds: ownAccountIds,
                existing: existing
            )
            return (duplicates, matches)
        }.value
        guard !Task.isCancelled else { return }
        duplicateReasons = duplicates
        transferMatches = matches

        // The other side of a transfer already in Tenra wins; otherwise what the
        // user did with the same description on this account before.
        var transfers: [String: String] = [:]
        for row in rows where row.type == .expense || row.type == .income {
            guard let accountId = mapping[row.id], duplicates[row.id] == nil else { continue }
            switch matches[row.id] {
            case .counterpart(_, let other):
                transfers[row.id] = other
            case .alreadyTransfer:
                continue
            case nil:
                let direction: ImportTransferHistory.Direction = row.type == .expense ? .outgoing : .incoming
                if let learned = ImportTransferHistory.counterpart(
                    accountId: accountId, direction: direction, description: row.description, in: transferHistory
                ), transferOptions(for: row, accountId: accountId).contains(where: { $0.id == learned }) {
                    transfers[row.id] = learned
                }
            }
        }
        transferMapping = transfers
        selectedTransactions = Set(rows.filter { startsSelected($0) }.map(\.id))
    }

    // MARK: - Transfers

    /// The user's other accounts a row can move money to or from: same currency,
    /// not the row's own account.
    private func transferOptions(for transaction: Transaction, accountId: String? = nil) -> [Account] {
        guard Self.isCategorizable(transaction) else { return [] }
        let own = accountId ?? accountMapping[transaction.id]
        return regularAccounts.filter { $0.currency == transaction.currency && $0.id != own }
    }

    private func selectTransfer(_ accountId: String, for transaction: Transaction) {
        withAnimation(AppAnimation.contentSpring) {
            if accountId.isEmpty {
                transferMapping.removeValue(forKey: transaction.id)
            } else {
                transferMapping[transaction.id] = accountId
            }
        }
    }

    /// The saved expense/income this row merges with: the matcher's counterpart,
    /// as long as the row is still a transfer to that same account.
    private func mergeTarget(for transaction: Transaction) -> Transaction? {
        guard case .counterpart(let existingId, let accountId) = transferMatches[transaction.id],
              transferMapping[transaction.id] == accountId else { return nil }
        return transactionStore.transactionById[existingId]
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
    /// not have, and the import would then drop the row silently. Anything that
    /// is not one of the user's categories saves as uncategorized.
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
            // A subcategory picked for the old category does not carry over.
            manuallySubcategorized.remove(transaction.id)
            refreshSubcategory(for: transaction)
            guard merchant.count >= CategorySuggestionService.minimumMerchantLength else { return }
            for other in transactions
            where other.id != transaction.id
                && other.type == transaction.type
                && !manuallyCategorized.contains(other.id)
                && CategorySuggestionService.normalizedMerchant(other.description) == merchant {
                categoryMapping[other.id] = name
                refreshSubcategory(for: other)
            }
        }
    }

    // MARK: - Subcategories

    /// The subcategories offered for the row's category: the ones linked to it,
    /// or every subcategory when none is linked yet (picking one links it).
    private func subcategoryOptions(for transaction: Transaction) -> [Subcategory] {
        guard Self.isCategorizable(transaction),
              let categoryId = categoryId(for: transaction) else { return [] }
        let linked = (transactionStore.subcategoryIdsByCategoryId[categoryId] ?? [])
            .compactMap { transactionStore.subcategoryById[$0] }
        guard linked.isEmpty else { return linked }
        return transactionStore.subcategories.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Resolved by name AND type: an income and an expense category may share a name.
    private func categoryId(for transaction: Transaction) -> String? {
        let category = effectiveCategory(for: transaction)
        guard !category.isEmpty else { return nil }
        return customCategories.first { $0.name == category && $0.type == transaction.type }?.id
    }

    /// Re-suggests the row's subcategory from history for its current category,
    /// unless the user picked one by hand.
    private func refreshSubcategory(for transaction: Transaction) {
        guard !manuallySubcategorized.contains(transaction.id) else { return }
        let category = effectiveCategory(for: transaction)
        if Self.isCategorizable(transaction), !category.isEmpty,
           let learned = CategorySuggestionService.historySubcategory(
               for: transaction.description, type: transaction.type, category: category, in: subcategoryHistory
           ),
           transactionStore.subcategoryById[learned] != nil {
            subcategoryMapping[transaction.id] = learned
        } else {
            subcategoryMapping.removeValue(forKey: transaction.id)
        }
    }

    /// Sets the row's subcategory and carries it to the other rows of the same
    /// merchant, type and category that the user has not set by hand.
    private func selectSubcategory(_ id: String, for transaction: Transaction) {
        let merchant = CategorySuggestionService.normalizedMerchant(transaction.description)
        let category = effectiveCategory(for: transaction)
        withAnimation(AppAnimation.contentSpring) {
            func assign(_ rowId: String) {
                if id.isEmpty { subcategoryMapping.removeValue(forKey: rowId) } else { subcategoryMapping[rowId] = id }
            }
            assign(transaction.id)
            manuallySubcategorized.insert(transaction.id)
            guard merchant.count >= CategorySuggestionService.minimumMerchantLength else { return }
            for other in transactions
            where other.id != transaction.id
                && other.type == transaction.type
                && !manuallySubcategorized.contains(other.id)
                && effectiveCategory(for: other) == category
                && CategorySuggestionService.normalizedMerchant(other.description) == merchant {
                assign(other.id)
            }
        }
    }

    private func savableSubcategoryIds(for transaction: Transaction) -> [String] {
        guard !savableCategory(for: transaction).isEmpty,
              let id = subcategoryMapping[transaction.id],
              transactionStore.subcategoryById[id] != nil else { return [] }
        return [id]
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

    // MARK: - Save

    private func addSelectedTransactions() {
        guard !isSaving else { return }
        isSaving = true
        // A row can only be selected when it has an account (see toggle/analyze),
        // but nothing without one may reach the store regardless of UI state:
        // accountId drives every balance calculation.
        let decisions: [ImportRowDecision] = transactions.compactMap { transaction in
            guard selectedTransactions.contains(transaction.id),
                  let accountId = accountMapping[transaction.id], !accountId.isEmpty else { return nil }
            let transferAccount = transferMapping[transaction.id]
            return ImportRowDecision(
                row: transaction,
                accountId: accountId,
                category: savableCategory(for: transaction),
                subcategoryIds: transferAccount == nil ? savableSubcategoryIds(for: transaction) : [],
                transferAccountId: transferAccount,
                mergeWith: mergeTarget(for: transaction)
            )
        }
        let operations = ImportCommitPlanner.operations(for: decisions)

        Task {
            let saved = await ImportCommitter.commit(
                operations,
                store: transactionStore,
                categories: categoriesViewModel,
                balance: accountsViewModel.balanceCoordinator
            )
            RatingPromptService.shared.recordTransactionAdded(count: saved)
            dismiss()
        }
    }
}

// MARK: - ImportRowNotice

/// Why a review row is flagged, most important first.
struct ImportMatchedRecord: Equatable {
    let label: String
    let date: String
}

struct ImportTransferRecord: Equatable {
    let from: String
    let to: String
    let date: String
}

enum ImportRowNotice: Equatable {
    /// Same account, type and amount within a day (ImportDuplicateDetector).
    case alreadyAdded(ImportMatchedRecord?)
    /// A charge a subscription series already generated.
    case subscription(ImportMatchedRecord?)
    /// A loan payment recorded through the loans screen from this account.
    case loanPayment(ImportMatchedRecord?)
    /// A saved transfer already moves this money in or out of the account.
    case alreadyTransfer(ImportTransferRecord?)
    /// The other side of a transfer is in Tenra on `accountName`; they merge.
    case merge(accountName: String, record: ImportMatchedRecord?)
    case cashWithdrawal
    case ownAccountMove

    var text: String {
        switch self {
        case .alreadyAdded(let record?):
            return String(format: String(localized: "transactionPreview.possibleDuplicateOf"), record.label, record.date)
        case .alreadyAdded(nil):
            return String(localized: "transactionPreview.possibleDuplicate")
        case .subscription(let record?):
            return String(format: String(localized: "transactionPreview.coveredBySubscriptionOf"), record.label, record.date)
        case .subscription(nil):
            return String(localized: "transactionPreview.coveredBySubscription")
        case .loanPayment(let record?):
            return String(format: String(localized: "transactionPreview.coveredByLoanPaymentOf"), record.label, record.date)
        case .loanPayment(nil):
            return String(localized: "transactionPreview.coveredByLoanPayment")
        case .alreadyTransfer(let record?):
            return String(format: String(localized: "transactionPreview.alreadyTransferOf"), record.from, record.to, record.date)
        case .alreadyTransfer(nil):
            return String(localized: "transactionPreview.alreadyTransfer")
        case .merge(let accountName, let record?):
            return String(format: String(localized: "transactionPreview.transferMergeOf"), record.label, accountName, record.date)
        case .merge(let accountName, nil):
            return String(format: String(localized: "transactionPreview.transferMerge"), accountName)
        case .cashWithdrawal:
            return String(localized: "transactionPreview.cashWithdrawal")
        case .ownAccountMove:
            return String(localized: "transactionPreview.ownAccountTransfer")
        }
    }

    var isWarning: Bool {
        switch self {
        case .alreadyAdded, .subscription, .loanPayment, .alreadyTransfer: return true
        case .merge, .cashWithdrawal, .ownAccountMove: return false
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
    let subcategory: Subcategory?
    let subcategoryOptions: [Subcategory]
    /// The user's other account when the row is saved as a transfer.
    let transferAccount: Account?
    let transferOptions: [Account]
    let notice: ImportRowNotice?
    let onCategorySelect: (String) -> Void
    let onSubcategorySelect: (String) -> Void
    let onTransferSelect: (String) -> Void

    private var isCategorizable: Bool {
        transaction.type == .expense || transaction.type == .income
    }

    private var isOutgoing: Bool { transaction.type == .expense }

    private var ownAccount: Account? {
        availableAccounts.first { $0.id == selectedAccountId }
    }

    // Resolved against the user's real categories, so a suggested category
    // shows its own icon and colour on the card.
    private var styleData: CategoryStyleData {
        CategoryStyleHelper.cached(category: displayTransaction.category, type: displayTransaction.type,
                                   customCategories: customCategories)
    }

    /// The card renders the row as it will be saved: with the effective category,
    /// or as a transfer between the two accounts.
    private var displayTransaction: Transaction {
        if let transferAccount {
            return Transaction(
                id: transaction.id,
                date: transaction.date,
                description: transaction.description,
                amount: transaction.amount,
                currency: transaction.currency,
                type: .internalTransfer,
                category: TransactionType.transferCategoryName,
                accountId: isOutgoing ? selectedAccountId : transferAccount.id,
                targetAccountId: isOutgoing ? transferAccount.id : selectedAccountId,
                accountName: isOutgoing ? ownAccount?.name : transferAccount.name,
                targetAccountName: isOutgoing ? transferAccount.name : ownAccount?.name,
                targetCurrency: transaction.currency,
                targetAmount: transaction.amount,
                createdAt: transaction.createdAt
            )
        }
        return Transaction(
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

    private var pickerSubcategories: [Subcategory] {
        guard let subcategory, !subcategoryOptions.contains(where: { $0.id == subcategory.id }) else {
            return subcategoryOptions
        }
        return subcategoryOptions + [subcategory]
    }

    /// No regular account exists in this transaction's currency. The row
    /// must stay unselectable (Fix 4): saving with a nil accountId makes the
    /// transaction invisible to every balance calculation, since accountId
    /// drives balance derivation throughout this codebase.
    private var hasNoMatchingAccount: Bool { availableAccounts.isEmpty }

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
                // never seen — this screen's own checkbox and pickers are the
                // only actions that make sense before import.
                TransactionCardView(
                    transaction: displayTransaction,
                    currency: transaction.currency,
                    styleData: styleData,
                    sourceAccount: transferAccount == nil ? nil : (isOutgoing ? ownAccount : transferAccount),
                    targetAccount: transferAccount == nil ? nil : (isOutgoing ? transferAccount : ownAccount),
                    linkedSubcategories: transferAccount == nil ? (subcategory.map { [$0] } ?? []) : []
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

            // Why the row is unchecked, or what saving it will do.
            if let notice {
                Text(notice.text)
                    .font(AppTypography.caption)
                    .foregroundStyle(notice.isWarning ? AppColors.warning : AppColors.textSecondary)
                    .padding(.leading, AppSpacing.xl)
            }

            // Account selector (visible only when selected)
            if isSelected && !availableAccounts.isEmpty {
                Picker(String(localized: "transactionPreview.account"), selection: Binding(
                    get: { selectedAccountId ?? "" },
                    set: { onAccountSelect($0) }
                )) {
                    ForEach(availableAccounts) { account in
                        Text("\(account.name) (\(Formatting.currencySymbol(for: account.currency)))").tag(account.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, AppSpacing.xl)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Transfer between own accounts (income/expense rows, visible only when selected)
            if isSelected && isCategorizable && !transferOptions.isEmpty {
                Picker(String(localized: isOutgoing ? "transactionPreview.transfer.to" : "transactionPreview.transfer.from"),
                       selection: Binding(
                        get: { transferAccount?.id ?? "" },
                        set: { onTransferSelect($0) }
                       )) {
                    Text(String(localized: "transactionPreview.transfer.none")).tag("")
                    ForEach(transferOptions) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, AppSpacing.xl)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Category and subcategory (income/expense rows that stay plain)
            if isSelected && isCategorizable && transferAccount == nil {
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

                if !category.isEmpty && !pickerSubcategories.isEmpty {
                    Picker(String(localized: "transactionPreview.subcategory"), selection: Binding(
                        get: { subcategory?.id ?? "" },
                        set: { onSubcategorySelect($0) }
                    )) {
                        Text(String(localized: "transactionPreview.noSubcategory")).tag("")
                        ForEach(pickerSubcategories) { subcategory in
                            Text(subcategory.name).tag(subcategory.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.leading, AppSpacing.xl)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
