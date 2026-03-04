//
//  EditTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Phase 16 (2026-02-17): Refactored to EditTransactionCoordinator pattern.
//  Replaced 12 @State variables with coordinator, added MessageBanner for errors.
//

import SwiftUI

struct EditTransactionView: View {

    // MARK: - Coordinator

    @State private var coordinator: EditTransactionCoordinator

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss

    // MARK: - Initialization

    init(
        transaction: Transaction,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        accounts: [Account],
        customCategories: [CustomCategory],
        balanceCoordinator: BalanceCoordinator
    ) {
        _coordinator = State(initialValue: EditTransactionCoordinator(
            transaction: transaction,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: transactionStore
        ))
        self._accounts = accounts
        self._customCategories = customCategories
        self._balanceCoordinator = balanceCoordinator
    }

    // MARK: - Stored Properties (passed from parent, used for UI components)

    private let _accounts: [Account]
    private let _customCategories: [CustomCategory]
    private let _balanceCoordinator: BalanceCoordinator

    // MARK: - Body

    var body: some View {
        @Bindable var bindableCoordinator = coordinator

        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Error banner
                        if let error = coordinator.errorMessage {
                            InlineStatusText(message: error, type: .error)
                                .padding(.horizontal, AppSpacing.pageHorizontal)
                        }

                        // 1. Amount + currency
                        AmountInputView(
                            amount: $bindableCoordinator.formData.amountText,
                            selectedCurrency: $bindableCoordinator.formData.selectedCurrency,
                            errorMessage: nil,
                            baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency
                        )

                        // 2. Account(s)
                        if !_accounts.isEmpty {
                            if coordinator.transaction.type == .internalTransfer {
                                AccountSelectorView(
                                    accounts: _accounts,
                                    selectedAccountId: $bindableCoordinator.formData.selectedAccountId,
                                    balanceCoordinator: _balanceCoordinator
                                )

                                AccountSelectorView(
                                    accounts: _accounts,
                                    selectedAccountId: $bindableCoordinator.formData.selectedTargetAccountId,
                                    balanceCoordinator: _balanceCoordinator
                                )
                                .padding(.top, AppSpacing.md)
                            } else {
                                AccountSelectorView(
                                    accounts: _accounts,
                                    selectedAccountId: $bindableCoordinator.formData.selectedAccountId,
                                    balanceCoordinator: _balanceCoordinator
                                )
                            }
                        }

                        // 3. Category + subcategories (not for transfers)
                        if coordinator.transaction.type != .internalTransfer {
                            CategorySelectorView(
                                categories: coordinator.availableCategories,
                                type: coordinator.transaction.type,
                                customCategories: _customCategories,
                                selectedCategory: Binding(
                                    get: { coordinator.formData.selectedCategory.isEmpty ? nil : coordinator.formData.selectedCategory },
                                    set: { coordinator.formData.selectedCategory = $0 ?? "" }
                                ),
                                emptyStateMessage: String(localized: "transactionForm.noCategories")
                            )

                            if coordinator.categoryId != nil {
                                SubcategorySelectorView(
                                    categoriesViewModel: coordinator.categoriesViewModel,
                                    categoryId: coordinator.categoryId,
                                    selectedSubcategoryIds: $bindableCoordinator.formData.selectedSubcategoryIds,
                                    onSearchTap: {
                                        withAnimation { coordinator.formData.showingSubcategorySearch = true }
                                    }
                                )
                            }
                        }

                        // 4. Recurring
                        MenuPickerRow(
                            title: String(localized: "quickAdd.makeRecurring"),
                            selection: $bindableCoordinator.formData.recurring
                        )

                        // 5. Description
                        DescriptionTextField(
                            text: $bindableCoordinator.formData.descriptionText,
                            placeholder: String(localized: "transactionForm.descriptionPlaceholder")
                        )
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: coordinator.errorMessage)
                }
            }
            .navigationTitle(String(localized: "transactionForm.editTransaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        coordinator.save { dismiss() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!coordinator.canSave)
                }
            }
            .dateButtonsSafeArea(selectedDate: $bindableCoordinator.formData.selectedDate) { date in
                coordinator.formData.selectedDate = date
                coordinator.save { dismiss() }
            }
            .sheet(isPresented: $bindableCoordinator.formData.showingSubcategorySearch) {
                SubcategorySearchView(
                    categoriesViewModel: coordinator.categoriesViewModel,
                    categoryId: coordinator.categoryId ?? "",
                    selectedSubcategoryIds: $bindableCoordinator.formData.selectedSubcategoryIds,
                    searchText: $bindableCoordinator.formData.subcategorySearchText
                )
                .onAppear {
                    coordinator.formData.subcategorySearchText = ""
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: coordinator.formData.selectedAccountId) { _, _ in
                coordinator.updateCurrencyForSelectedAccount()
            }
            .onChange(of: coordinator.formData.recurring) { oldValue, newValue in
                if newValue == .never, case .frequency = oldValue {
                    if coordinator.transaction.recurringSeriesId != nil {
                        coordinator.handleRecurringDisabled()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Edit Expense") {
    let coordinator = AppCoordinator()
    let mockAccounts = [
        Account(id: "acc-kaspi", name: "Kaspi Gold", currency: "KZT", iconSource: .bankLogo(.kaspi), initialBalance: 150000),
        Account(id: "acc-halyk", name: "Halyk Bank", currency: "KZT", iconSource: .bankLogo(.halykBank), initialBalance: 80000)
    ]
    let sampleTransaction = Transaction(
        id: "test",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Обед в кафе",
        amount: 3500,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: "acc-kaspi"
    )
    return NavigationStack {
        EditTransactionView(
            transaction: sampleTransaction,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionStore: coordinator.transactionStore,
            accounts: mockAccounts,
            customCategories: coordinator.categoriesViewModel.customCategories,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
        )
    }
    .environment(coordinator.transactionStore)
}

#Preview("Edit Income") {
    let coordinator = AppCoordinator()
    let mockAccounts = [
        Account(id: "acc-halyk", name: "Halyk Bank", currency: "KZT", iconSource: .bankLogo(.halykBank), initialBalance: 500000)
    ]
    let sampleTransaction = Transaction(
        id: "test-income",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Зарплата",
        amount: 450000,
        currency: "KZT",
        type: .income,
        category: "Salary",
        accountId: "acc-halyk"
    )
    return NavigationStack {
        EditTransactionView(
            transaction: sampleTransaction,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionStore: coordinator.transactionStore,
            accounts: mockAccounts,
            customCategories: coordinator.categoriesViewModel.customCategories,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
        )
    }
    .environment(coordinator.transactionStore)
}
