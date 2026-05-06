//
//  AccountActionView.swift
//  Tenra
//

import SwiftUI

struct AccountActionView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    let account: Account
    let namespace: Namespace.ID
    @Environment(\.dismiss) var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @State private var viewModel: AccountActionViewModel
    @State private var showingAccountHistory = false

    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        account: Account,
        namespace: Namespace.ID,
        categoriesViewModel: CategoriesViewModel,
        defaultAction: AccountActionViewModel.ActionType? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.account = account
        self.namespace = namespace
        self.categoriesViewModel = categoriesViewModel
        _viewModel = State(initialValue: AccountActionViewModel(
            account: account,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel,
            defaultAction: defaultAction
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Color.clear
                    .frame(height: 0)
                    .glassEffectID("account-card-\(account.id)", in: namespace)

                fromSection

                toSection

                AmountInputView(
                    amount: $viewModel.amountText,
                    selectedCurrency: $viewModel.selectedCurrency,
                    errorMessage: viewModel.showingError ? viewModel.errorMessage : nil,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                    accountCurrencies: Set(accountsViewModel.accounts.map(\.currency)),
                    appSettings: transactionsViewModel.appSettings
                )

                FormTextField(
                    text: $viewModel.descriptionText,
                    placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
                    style: .multiline(min: 2, max: 6)
                )
            }
        }
        .safeAreaBar(edge: .top) { topBar }
        .navigationTitle(viewModel.navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .dateButtonsSafeArea(selectedDate: $viewModel.selectedDate, onSave: { date in
            Task { await viewModel.saveTransaction(date: date, transactionStore: transactionStore) }
        })
        .sheet(isPresented: $showingAccountHistory) {
            NavigationStack {
                HistoryView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    paginationController: appCoordinator.transactionPaginationController,
                    initialAccountId: account.id
                )
                    .environment(timeFilterManager)
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, should in
            if should { dismiss() }
        }
        .alert(String(localized: "common.error"), isPresented: $viewModel.showingError) {
            Button(String(localized: "voice.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var fromSection: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "transactionForm.fromHeader"))
                .padding(.horizontal, AppSpacing.lg)

            switch viewModel.selectedAction {
            case .transfer:
                if let coordinator = accountsViewModel.balanceCoordinator {
                    AccountSelectorView(
                        accounts: viewModel.availableSourceAccounts,
                        selectedAccountId: $viewModel.selectedSourceAccountId,
                        onSelectionChange: { _ in
                            viewModel.updateCurrencyForPrimaryAccount()
                        },
                        emptyStateMessage: String(localized: "transactionForm.noAccountsForTransfer"),
                        balanceCoordinator: coordinator
                    )
                }
            case .income:
                CategorySelectorView(
                    categories: viewModel.incomeCategories,
                    type: .income,
                    customCategories: transactionsViewModel.customCategories,
                    selectedCategory: $viewModel.selectedCategory,
                    emptyStateMessage: String(localized: "transactionForm.noCategories")
                )
            }
        }
    }

    @ViewBuilder
    private var toSection: some View {
        @Bindable var viewModel = viewModel
        if let coordinator = accountsViewModel.balanceCoordinator {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SectionHeaderView(String(localized: "transactionForm.toHeader"))
                    .padding(.horizontal, AppSpacing.lg)

                AccountSelectorView(
                    accounts: viewModel.availableTargetAccounts,
                    selectedAccountId: $viewModel.selectedTargetAccountId,
                    onSelectionChange: { _ in
                        viewModel.updateCurrencyForPrimaryAccount()
                    },
                    emptyStateMessage: String(localized: "transactionForm.noAccountsForTransfer"),
                    balanceCoordinator: coordinator
                )
            }
        }
    }

    // MARK: - Top bar / Toolbar

    private var topBar: some View {
        @Bindable var viewModel = viewModel
        return SegmentedPickerView(
            title: String(localized: "common.type"),
            selection: $viewModel.selectedAction,
            options: [
                (label: String(localized: "transactionForm.transfer"), value: AccountActionViewModel.ActionType.transfer),
                (label: String(localized: "transactionForm.topUp"), value: AccountActionViewModel.ActionType.income)
            ]
        )
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(Color.clear)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                showingAccountHistory = true
            }) {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
    }
}

#Preview {
    @Previewable @Namespace var ns
    let coordinator = AppCoordinator()
    return NavigationStack {
        AccountActionView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            account: Account(name: "Main", currency: "USD", iconSource: nil, initialBalance: 1000),
            namespace: ns,
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
    .environment(coordinator)
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
