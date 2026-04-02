//
//  AccountActionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountActionView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TransactionStore.self) private var transactionStore // Phase 7.4: TransactionStore integration
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
        transferDirection: DepositTransferDirection? = nil
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
            transferDirection: transferDirection
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Color.clear
                    .frame(height: 0)
                    .glassEffectID("account-card-\(account.id)", in: namespace) // glass morph anchor

                // 2. Сумма с выбором валюты
                AmountInputView(
                    amount: $viewModel.amountText,
                    selectedCurrency: $viewModel.selectedCurrency,
                    errorMessage: viewModel.showingError ? viewModel.errorMessage : nil,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )

                // 3. Счет
                if viewModel.selectedAction == .income && !account.isDeposit {
                    // Для пополнения счет не нужен
                    EmptyView()
                } else {
                    if let coordinator = accountsViewModel.balanceCoordinator {
                        AccountSelectorView(
                            accounts: viewModel.availableAccounts,
                            selectedAccountId: $viewModel.selectedTargetAccountId,
                            emptyStateMessage: String(localized: "transactionForm.noAccountsForTransfer"),
                            balanceCoordinator: coordinator
                        )
                    }
                }

                // 4. Категория (только для пополнения)
                if viewModel.selectedAction == .income && !account.isDeposit {
                    CategorySelectorView(
                        categories: viewModel.incomeCategories,
                        type: .income,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $viewModel.selectedCategory,
                        emptyStateMessage: String(localized: "transactionForm.noCategories")
                    )
                }

                // 5. Описание
                FormTextField(
                    text: $viewModel.descriptionText,
                    placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
                    style: .multiline(min: 2, max: 6)
                )
            }
        }
        .safeAreaInset(edge: .top) {
            if !account.isDeposit {
                SegmentedPickerView(
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
        }
        .navigationTitle(viewModel.navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAccountHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
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
}

// CategoryRadioButton is now replaced by CategoryChip

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
