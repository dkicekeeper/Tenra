//
//  TransactionCard.swift
//  Tenra
//
//  Reusable transaction card component for displaying transactions in lists
//

import SwiftUI

struct TransactionCard: View {
    let transaction: Transaction
    let currency: String
    /// Pre-resolved style data for this transaction's category.
    /// Passed pre-computed from the call site so that changes to other categories
    /// do not force a re-render of rows whose category is unaffected.
    let styleData: CategoryStyleData
    /// The account referenced by `transaction.accountId` (nil if deleted or unknown).
    /// Passed pre-resolved so that balance updates to other accounts do not trigger
    /// a re-render of rows that reference a different account.
    let sourceAccount: Account?
    /// The target account for internal transfers (`transaction.targetAccountId`). Nil otherwise.
    let targetAccount: Account?
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel?
    let balanceCoordinator: BalanceCoordinator?  // Optional - can't use @ObservedObject with optionals

    // MARK: - Convenience

    /// Small [Account] array built from pre-resolved source/target for subviews
    /// that still accept [Account] (TransactionInfoView, accessibilityText).
    private var resolvedAccounts: [Account] {
        [sourceAccount, targetAccount].compactMap { $0 }
    }

    @State private var showingStopRecurringConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditModal = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingResumeError = false
    @State private var resumeErrorMessage = ""

    // TransactionStore for delete and edit operations
    @Environment(TransactionStore.self) private var transactionStore

    /// Icon source from the subscription series linked to this transaction (nil for generic recurring)
    private var subscriptionIconSource: IconSource? {
        guard let seriesId = transaction.recurringSeriesId else { return nil }
        let series = transactionStore.recurringSeries.first(where: { $0.id == seriesId })
        guard series?.kind == .subscription else { return nil }
        return series?.iconSource
    }

    /// Badge is shown only for future transactions whose recurring series is still active.
    /// Past/executed transactions and stopped series never show the badge.
    private var showRecurringBadge: Bool {
        guard let seriesId = transaction.recurringSeriesId else { return false }
        guard isFutureDate else { return false }
        return transactionStore.recurringSeries.first(where: { $0.id == seriesId })?.isActive ?? false
    }

    /// The recurring series linked to this transaction, if it still exists in the store.
    private var linkedRecurringSeries: RecurringSeries? {
        guard let seriesId = transaction.recurringSeriesId else { return nil }
        return transactionStore.recurringSeries.first(where: { $0.id == seriesId })
    }

    /// True when the linked series exists and is currently active (generates future transactions).
    private var isSeriesActive: Bool {
        linkedRecurringSeries?.isActive ?? false
    }

    init(
        transaction: Transaction,
        currency: String,
        styleData: CategoryStyleData,
        sourceAccount: Account? = nil,
        targetAccount: Account? = nil,
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil
    ) {
        self.transaction = transaction
        self.currency = currency
        self.styleData = styleData
        self.sourceAccount = sourceAccount
        self.targetAccount = targetAccount
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.balanceCoordinator = balanceCoordinator
    }
    
    // MARK: - Display Helpers

    private var isFutureDate: Bool {
        TransactionDisplayHelper.isFutureDate(transaction.date)
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Transaction icon
            TransactionIconView(
                transaction: transaction,
                styleData: styleData,
                subscriptionIconSource: subscriptionIconSource,
                showRecurringBadge: showRecurringBadge
            )
            
            // Transaction info
            TransactionInfoView(
                transaction: transaction,
                accounts: resolvedAccounts,
                linkedSubcategories: categoriesViewModel?.getSubcategoriesForTransaction(transaction.id) ?? []
            )
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if transaction.type == .internalTransfer {
                    transferAmountView
                } else {
                    FormattedAmountView(
                        amount: transaction.amount,
                        currency: transaction.currency,
                        prefix: amountPrefix,
                        color: amountColor
                    )

                    // Если есть вторая валюта (мультивалютные транзакции)
                    if let targetCurrency = transaction.targetCurrency,
                       let targetAmount = transaction.targetAmount,
                       targetCurrency != transaction.currency {
                        FormattedAmountView(
                            amount: targetAmount,
                            currency: targetCurrency,
                            prefix: "",
                            color: amountColor.opacity(0.7)
                        )
                    }
                }
            }
        }
        .futureTransactionStyle(isFuture: isFutureDate)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(String(localized: "accessibility.swipeForOptions"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Удаление
            Button(role: .destructive) {
                HapticManager.warning()
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
            .accessibilityLabel(String(localized: "accessibility.deleteTransaction"))

            // Stop Recurring — shown only when series exists and is active
            if isSeriesActive {
                Button {
                    showingStopRecurringConfirmation = true
                } label: {
                    Label(String(localized: "transaction.recurring"), systemImage: "arrow.clockwise")
                }
                .tint(AppColors.accent)
                .accessibilityLabel(String(localized: "accessibility.stopRecurring"))
            }

            // Resume Recurring — shown when series exists but was stopped
            if !isSeriesActive, linkedRecurringSeries != nil {
                Button {
                    HapticManager.selection()
                    Task {
                        do {
                            guard let seriesId = transaction.recurringSeriesId else { return }

                            // Read subcategory IDs from the current transaction — they serve
                            // as the template for any newly generated occurrences.
                            let subcategoryIds = categoriesViewModel?
                                .getSubcategoriesForTransaction(transaction.id)
                                .map { $0.id } ?? []

                            // Snapshot IDs before resume so we can find newly generated txs.
                            let idsBefore = Set(transactionStore.transactions.map { $0.id })

                            try await transactionStore.resumeSeries(id: seriesId)

                            // Link subcategories to every newly generated transaction.
                            if !subcategoryIds.isEmpty, let catVM = categoriesViewModel {
                                let idsAfter = Set(transactionStore.transactions.map { $0.id })
                                let newIds = idsAfter.subtracting(idsBefore)
                                for id in newIds {
                                    catVM.linkSubcategoriesToTransaction(
                                        transactionId: id,
                                        subcategoryIds: subcategoryIds
                                    )
                                }
                            }

                            HapticManager.success()
                        } catch {
                            await MainActor.run {
                                resumeErrorMessage = error.localizedDescription
                                showingResumeError = true
                                HapticManager.error()
                            }
                        }
                    }
                } label: {
                    Label(String(localized: "transaction.resumeRecurring", defaultValue: "Resume"), systemImage: "play.circle")
                }
                .tint(AppColors.success)
                .accessibilityLabel(String(localized: "transaction.resumeRecurring", defaultValue: "Resume Recurring"))
            }
        }
        .alert(String(localized: "transaction.stopRecurring.title"), isPresented: $showingStopRecurringConfirmation) {
            Button(String(localized: "transaction.stopRecurring.cancel"), role: .cancel) {}
            Button(String(localized: "transaction.stopRecurring.confirm"), role: .destructive) {
                HapticManager.warning()
                if let viewModel = viewModel, let seriesId = transaction.recurringSeriesId {
                    viewModel.stopRecurringSeriesAndCleanup(seriesId: seriesId, transactionDate: transaction.date)
                }
            }
        } message: {
            Text(String(localized: "transaction.stopRecurring.message"))
        }
        .confirmationDialog(
            String(localized: "transaction.deleteConfirmation.title", defaultValue: "Delete Transaction?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "button.delete", defaultValue: "Delete"), role: .destructive) {
                Task {
                    do {
                        try await transactionStore.delete(transaction)
                        HapticManager.success()
                    } catch {
                        deleteErrorMessage = error.localizedDescription
                        showingDeleteError = true
                        HapticManager.error()
                    }
                }
            }
        }
        .alert(String(localized: "error.generic.title", defaultValue: "Error"), isPresented: $showingDeleteError) {
            Button(String(localized: "button.ok"), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
        .alert(String(localized: "error.generic.title", defaultValue: "Error"), isPresented: $showingResumeError) {
            Button(String(localized: "button.ok"), role: .cancel) {}
        } message: {
            Text(resumeErrorMessage)
        }
        .onTapGesture {
            HapticManager.selection()
            showingEditModal = true
        }
        .sheet(isPresented: $showingEditModal) {
            if let viewModel = viewModel,
               let catVM = categoriesViewModel,
               let accVM = accountsViewModel,
               let balanceCoordinator = balanceCoordinator {
                TransactionEditView(
                    transaction: transaction,
                    transactionsViewModel: viewModel,
                    categoriesViewModel: catVM,
                    accountsViewModel: accVM,
                    transactionStore: transactionStore,
                    accounts: accVM.accounts,             // full list — only read when sheet opens
                    customCategories: catVM.customCategories,
                    balanceCoordinator: balanceCoordinator
                )
            }
        }
    }
    
    private var accessibilityText: String {
        TransactionDisplayHelper.accessibilityText(for: transaction, accounts: resolvedAccounts)
    }

    private var amountColor: Color {
        TransactionDisplayHelper.amountColor(for: transaction.type)
    }

    private var amountPrefix: String {
        TransactionDisplayHelper.amountPrefix(for: transaction.type)
    }
    
    private var transferAmountView: some View {
        TransferAmountView(
            transaction: transaction,
            sourceAccount: sourceAccount,
            targetAccount: targetAccount,
            depositAccountId: nil
        )
    }
}

#Preview("Expense") {
    let coordinator = AppCoordinator()
    let kaspi = Account(id: "acc-kaspi", name: "Kaspi Gold", currency: "KZT", iconSource: .brandService("kaspi.kz"), initialBalance: 150000)
    let sampleTransaction = Transaction(
        id: "preview-expense",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Кофе и перекус",
        amount: 2500,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: "acc-kaspi"
    )
    let styleData = CategoryStyleHelper.cached(category: sampleTransaction.category, type: sampleTransaction.type, customCategories: [])

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            styleData: styleData,
            sourceAccount: kaspi,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}

#Preview("Income") {
    let coordinator = AppCoordinator()
    let halyk = Account(id: "acc-halyk", name: "Halyk Bank", currency: "KZT", iconSource: .brandService("halykbank.kz"), initialBalance: 500000)
    let sampleTransaction = Transaction(
        id: "preview-income",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Зарплата",
        amount: 450000,
        currency: "KZT",
        type: .income,
        category: "Salary",
        accountId: "acc-halyk"
    )
    let styleData = CategoryStyleHelper.cached(category: sampleTransaction.category, type: sampleTransaction.type, customCategories: [])

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            styleData: styleData,
            sourceAccount: halyk,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}

#Preview("Transfer") {
    let coordinator = AppCoordinator()
    let src = Account(id: "acc-src", name: "Kaspi Gold", currency: "KZT", iconSource: .brandService("kaspi.kz"), initialBalance: 150000)
    let tgt = Account(id: "acc-tgt", name: "Halyk Bank", currency: "KZT", iconSource: .brandService("halykbank.kz"), initialBalance: 250000)
    let sampleTransaction = Transaction(
        id: "preview-transfer",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Перевод между счетами",
        amount: 50000,
        currency: "KZT",
        type: .internalTransfer,
        category: "Transfer",
        accountId: "acc-src",
        targetAccountId: "acc-tgt"
    )
    let styleData = CategoryStyleHelper.cached(category: sampleTransaction.category, type: sampleTransaction.type, customCategories: [])

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            styleData: styleData,
            sourceAccount: src,
            targetAccount: tgt,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}

#Preview("Recurring") {
    let coordinator = AppCoordinator()
    let kaspi = Account(id: "acc-kaspi", name: "Kaspi Gold", currency: "KZT", iconSource: .brandService("kaspi.kz"), initialBalance: 150000)
    let sampleTransaction = Transaction(
        id: "preview-recurring",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Netflix",
        amount: 4990,
        currency: "KZT",
        type: .expense,
        category: "Subscriptions",
        accountId: "acc-kaspi",
        recurringSeriesId: "series-1"
    )
    let styleData = CategoryStyleHelper.cached(category: sampleTransaction.category, type: sampleTransaction.type, customCategories: [])

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            styleData: styleData,
            sourceAccount: kaspi,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}
