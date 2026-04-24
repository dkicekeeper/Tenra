//
//  TransactionCard.swift
//  Tenra
//
//  Interactive transaction row: tap → edit sheet, swipe → delete / stop-resume recurring.
//  Thin wrapper over `TransactionCardView` (pure UI). Resolves recurring-series state
//  from `TransactionStore` and subcategories from `CategoriesViewModel`.
//
//  For read-only / selection UIs use `TransactionCardView` directly — it has no env
//  dependencies and no side effects.
//

import SwiftUI

struct TransactionCard: View {
    let transaction: Transaction
    let currency: String
    let styleData: CategoryStyleData
    let sourceAccount: Account?
    let targetAccount: Account?
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel?
    let balanceCoordinator: BalanceCoordinator?

    @State private var showingStopRecurringConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditModal = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingResumeError = false
    @State private var resumeErrorMessage = ""

    @Environment(TransactionStore.self) private var transactionStore

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

    private var isFutureDate: Bool {
        TransactionDisplayHelper.isFutureDate(transaction.date)
    }

    private var linkedRecurringSeries: RecurringSeries? {
        guard let seriesId = transaction.recurringSeriesId else { return nil }
        return transactionStore.recurringSeries.first(where: { $0.id == seriesId })
    }

    private var isSeriesActive: Bool {
        linkedRecurringSeries?.isActive ?? false
    }

    private var subscriptionIconSource: IconSource? {
        guard let series = linkedRecurringSeries, series.kind == .subscription else { return nil }
        return series.iconSource
    }

    private var showRecurringBadge: Bool {
        guard transaction.recurringSeriesId != nil, isFutureDate else { return false }
        return isSeriesActive
    }

    private var linkedSubcategories: [Subcategory] {
        categoriesViewModel?.getSubcategoriesForTransaction(transaction.id) ?? []
    }

    var body: some View {
        TransactionCardView(
            transaction: transaction,
            currency: currency,
            styleData: styleData,
            sourceAccount: sourceAccount,
            targetAccount: targetAccount,
            subscriptionIconSource: subscriptionIconSource,
            showRecurringBadge: showRecurringBadge,
            linkedSubcategories: linkedSubcategories
        )
        .accessibilityHint(Text(String(localized: "accessibility.swipeForOptions")))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Удаление — НЕ используем role: .destructive, т.к. он заставляет
            // SwiftUI анимированно удалить строку сразу по тапу, что дизмиссит
            // confirmationDialog до того, как пользователь подтвердит.
            Button {
                HapticManager.warning()
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
            .tint(.red)
            .accessibilityLabel(String(localized: "accessibility.deleteTransaction"))

            if isSeriesActive {
                Button {
                    showingStopRecurringConfirmation = true
                } label: {
                    Label(String(localized: "transaction.recurring"), systemImage: "arrow.clockwise")
                }
                .tint(AppColors.accent)
                .accessibilityLabel(String(localized: "accessibility.stopRecurring"))
            }

            if !isSeriesActive, linkedRecurringSeries != nil {
                Button {
                    HapticManager.selection()
                    Task { await resumeRecurringSeries() }
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
                    accounts: accVM.accounts,
                    customCategories: catVM.customCategories,
                    balanceCoordinator: balanceCoordinator
                )
            }
        }
    }

    private func resumeRecurringSeries() async {
        do {
            guard let seriesId = transaction.recurringSeriesId else { return }

            let subcategoryIds = categoriesViewModel?
                .getSubcategoriesForTransaction(transaction.id)
                .map { $0.id } ?? []

            let idsBefore = Set(transactionStore.transactions.map { $0.id })

            try await transactionStore.resumeSeries(id: seriesId)

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
}


// MARK: - Previews

#Preview("Expense") {
    let coordinator = AppCoordinator()
    let kaspi = Account(id: "acc-kaspi", name: "Kaspi Gold", currency: "KZT",
                        iconSource: .brandService("kaspi.kz"), initialBalance: 150_000)
    let tx = Transaction(
        id: "preview-expense",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Кофе и перекус",
        amount: 2_500,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: "acc-kaspi"
    )
    let style = CategoryStyleHelper.cached(category: tx.category, type: tx.type, customCategories: [])

    List {
        TransactionCard(
            transaction: tx,
            currency: "KZT",
            styleData: style,
            sourceAccount: kaspi,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(.plain)
    .environment(coordinator.transactionStore)
}

#Preview("Transfer") {
    let coordinator = AppCoordinator()
    let src = Account(id: "acc-src", name: "Kaspi Gold", currency: "KZT",
                      iconSource: .brandService("kaspi.kz"), initialBalance: 150_000)
    let tgt = Account(id: "acc-tgt", name: "Halyk Bank", currency: "KZT",
                      iconSource: .brandService("halykbank.kz"), initialBalance: 250_000)
    let tx = Transaction(
        id: "preview-transfer",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Перевод",
        amount: 50_000,
        currency: "KZT",
        type: .internalTransfer,
        category: "Transfer",
        accountId: "acc-src",
        targetAccountId: "acc-tgt"
    )
    let style = CategoryStyleHelper.cached(category: tx.category, type: tx.type, customCategories: [])

    List {
        TransactionCard(
            transaction: tx,
            currency: "KZT",
            styleData: style,
            sourceAccount: src,
            targetAccount: tgt,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(.plain)
    .environment(coordinator.transactionStore)
}
