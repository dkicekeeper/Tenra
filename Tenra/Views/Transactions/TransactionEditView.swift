//
//  TransactionEditView.swift
//  Tenra
//
//  Created on 2024
//  Phase 16 (2026-02-17): Refactored to TransactionEditCoordinator pattern.
//  Replaced 12 @State variables with coordinator, added MessageBanner for errors.
//

import SwiftUI

struct TransactionEditView: View {

    // MARK: - Coordinator

    @State private var coordinator: TransactionEditCoordinator

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
        _coordinator = State(initialValue: TransactionEditCoordinator(
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
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                        // Hero: category icon + name (or transfer icon)
                        SimpleHeroSection(
                            iconSource: heroIconSource,
                            title: heroTitle
                        )

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
                            baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
                            accountCurrencies: Set(_accounts.map(\.currency)),
                            appSettings: coordinator.transactionsViewModel.appSettings
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
                                    },
                                    onReorderTap: {
                                        coordinator.formData.showingSubcategoryReorder = true
                                    }
                                )
                            }
                        }

                        // 4. Description
                        FormTextField(
                            text: $bindableCoordinator.formData.descriptionText,
                            placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
                            style: .multiline(min: 2, max: 6)
                        )
                        .screenPadding()
                    }
                .animation(AppAnimation.gentleSpring, value: coordinator.errorMessage)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
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
            .sheet(isPresented: $bindableCoordinator.formData.showingSubcategoryReorder) {
                if let categoryId = coordinator.categoryId {
                    SubcategoryReorderView(
                        categoriesViewModel: coordinator.categoriesViewModel,
                        categoryId: categoryId
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
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

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "button.close"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                recurringMenuButton
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    coordinator.save { dismiss() }
                } label: {
                    Image(systemName: "checkmark")
                }
                .glassProminentButton()
                .disabled(!coordinator.canSave)
                .accessibilityLabel(String(localized: "button.save"))
            }
        }
    }

    private var recurringMenuButton: some View {
        let isActive = coordinator.formData.recurring != .never
        return Menu {
            Button {
                coordinator.formData.recurring = .never
            } label: {
                if coordinator.formData.recurring == .never {
                    Label(String(localized: "recurring.never"), systemImage: "checkmark")
                } else {
                    Text(String(localized: "recurring.never"))
                }
            }
            ForEach(RecurringFrequency.allCases, id: \.self) { freq in
                Button {
                    coordinator.formData.recurring = .frequency(freq)
                } label: {
                    if coordinator.formData.recurring == .frequency(freq) {
                        Label(freq.displayName, systemImage: "checkmark")
                    } else {
                        Text(freq.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "repeat")
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
    }

    // MARK: - Hero Helpers

    private var heroCategory: CustomCategory? {
        guard coordinator.transaction.type != .internalTransfer else { return nil }
        return _customCategories.first { $0.name == coordinator.formData.selectedCategory }
    }

    private var heroIconSource: IconSource? {
        if coordinator.transaction.type == .internalTransfer {
            return .sfSymbol("arrow.left.arrow.right")
        }
        return heroCategory?.iconSource
    }

    private var heroTitle: String {
        if coordinator.transaction.type == .internalTransfer {
            return String(localized: "transaction.type.internalTransfer", defaultValue: "Transfer")
        }
        return coordinator.formData.selectedCategory
    }
}

// MARK: - Preview

#Preview("Edit Expense") {
    let coordinator = AppCoordinator()
    let mockAccounts = [
        Account(id: "acc-kaspi", name: "Kaspi Gold", currency: "KZT", iconSource: .brandService("kaspi.kz"), initialBalance: 150000),
        Account(id: "acc-halyk", name: "Halyk Bank", currency: "KZT", iconSource: .brandService("halykbank.kz"), initialBalance: 80000)
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
    NavigationStack {
        TransactionEditView(
            transaction: sampleTransaction,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionStore: coordinator.transactionStore,
            accounts: mockAccounts,
            customCategories: coordinator.categoriesViewModel.customCategories,
            balanceCoordinator: coordinator.balanceCoordinator
        )
    }
    .environment(coordinator.transactionStore)
}

#Preview("Edit Income") {
    let coordinator = AppCoordinator()
    let mockAccounts = [
        Account(id: "acc-halyk", name: "Halyk Bank", currency: "KZT", iconSource: .brandService("halykbank.kz"), initialBalance: 500000)
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
    NavigationStack {
        TransactionEditView(
            transaction: sampleTransaction,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionStore: coordinator.transactionStore,
            accounts: mockAccounts,
            customCategories: coordinator.categoriesViewModel.customCategories,
            balanceCoordinator: coordinator.balanceCoordinator
        )
    }
    .environment(coordinator.transactionStore)
}
