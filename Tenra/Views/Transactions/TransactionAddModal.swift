//
//  TransactionAddModal.swift
//  Tenra
//
//  Modal form for adding a transaction from the category picker grid.
//  Refactored to use TransactionAddCoordinator for business logic.
//

import SwiftUI

struct TransactionAddModal: View {

    // MARK: - Coordinator

    @State private var coordinator: TransactionAddCoordinator

    // MARK: - Environment

    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - State

    @State private var validationError: String?
    @State private var isSaving = false
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var showingSubcategoryReorder = false
    @State private var showingCategoryHistory = false

    @Namespace private var historyNamespace

    // MARK: - Callbacks

    let onDismiss: () -> Void

    // MARK: - Initialization

    init(
        category: String,
        type: TransactionType,
        currency: String,
        accounts: [Account],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        onDismiss: @escaping () -> Void
    ) {
        // ✅ REFACTORED: TransactionStore now passed directly, not via @EnvironmentObject
        _coordinator = State(initialValue: TransactionAddCoordinator(
            category: category,
            type: type,
            currency: currency,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: transactionStore
        ))
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    var body: some View {
        @Bindable var bindableCoordinator = coordinator

        NavigationStack {
            VStack(spacing: 0) {
                formContent
                    .sheet(isPresented: $showingSubcategorySearch) {
                        subcategorySearchSheet
                    }
                    .sheet(isPresented: $showingSubcategoryReorder) {
                        if let categoryId {
                            SubcategoryReorderView(
                                categoriesViewModel: coordinator.categoriesViewModel,
                                categoryId: categoryId
                            )
                            .presentationDetents([.medium])
                            .presentationDragIndicator(.visible)
                        }
                    }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .dateButtonsSafeArea(
                selectedDate: $bindableCoordinator.formData.selectedDate,
                isDisabled: isSaving,
                onSave: { date in
                    coordinator.formData.selectedDate = date
                    Task { await saveTransaction() }
                }
            )
            .overlay(overlayContent)
            .navigationDestination(isPresented: $showingCategoryHistory) {
                categoryHistoryDestination
            }
            .onChange(of: coordinator.formData.accountId) { _, _ in
                coordinator.updateCurrencyForSelectedAccount()
            }
            .task {
                // ✅ REFACTORED: Simplified account suggestion
                // SwiftUI's .task{} automatically handles lifecycle
                if coordinator.formData.accountId == nil {
                    coordinator.formData.accountId = await coordinator.suggestedAccountId()
                    coordinator.updateCurrencyForSelectedAccount()
                } else {
                    coordinator.updateCurrencyForSelectedAccount()
                }
            }
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        @Bindable var bindableCoordinator = coordinator

        return ScrollView {
            VStack(spacing: AppSpacing.lg) {
                HeroSection(
                    iconSource: categoryData?.iconSource,
                    title: coordinator.formData.category
                )

                AmountInputView(
                    amount: $bindableCoordinator.formData.amountText,
                    selectedCurrency: $bindableCoordinator.formData.currency,
                    errorMessage: validationError,
                    baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
                    accountCurrencies: Set(coordinator.accountsViewModel.accounts.map(\.currency)),
                    appSettings: coordinator.transactionsViewModel.appSettings,
                    onAmountChange: { _ in
                        validationError = nil
                    }
                )

                if !coordinator.rankedAccounts().isEmpty {
                    AccountSelectorView(
                        accounts: coordinator.rankedAccounts(),
                        // ✅ PERFORMANCE FIX: Simple binding - no heavy computation in get
                        // Suggested account is set asynchronously in onAppear
                        selectedAccountId: $bindableCoordinator.formData.accountId,
                        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
                    )
                }

                if categoryId != nil {
                    SubcategorySelectorView(
                        categoriesViewModel: coordinator.categoriesViewModel,
                        categoryId: categoryId,
                        selectedSubcategoryIds: $bindableCoordinator.formData.subcategoryIds,
                        onSearchTap: {
                            showingSubcategorySearch = true
                        },
                        onReorderTap: {
                            showingSubcategoryReorder = true
                        }
                    )
                }

                FormTextField(
                    text: $bindableCoordinator.formData.description,
                    placeholder: String(localized: "quickAdd.descriptionPlaceholder"),
                    style: .multiline(min: 2, max: 6)
                )
                .screenPadding()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "button.close"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                recurringMenuButton
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showingCategoryHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel(String(localized: "accessibility.transaction.history"))
                .matchedTransitionSource(id: "history", in: historyNamespace)
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

    // MARK: - Overlay

    private var overlayContent: some View {
        Group {
            if isSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                    .accessibilityLabel(String(localized: "progress.saving"))
            }
        }
    }

    // MARK: - Sheets

    private var subcategorySearchSheet: some View {
        @Bindable var bindableCoordinator = coordinator

        return SubcategorySearchView(
            categoriesViewModel: coordinator.categoriesViewModel,
            categoryId: categoryId ?? "",
            selectedSubcategoryIds: $bindableCoordinator.formData.subcategoryIds,
            searchText: $subcategorySearchText
        )
        .onAppear {
            subcategorySearchText = ""
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var categoryHistoryDestination: some View {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            paginationController: appCoordinator.transactionPaginationController,
            initialCategory: coordinator.formData.category
        )
        .environment(timeFilterManager)
        .navigationTransition(.zoom(sourceID: "history", in: historyNamespace))
    }

    // MARK: - Private Methods

    private var categoryData: CustomCategory? {
        coordinator.categoriesViewModel.customCategories.first {
            $0.name == coordinator.formData.category
        }
    }

    private var categoryId: String? {
        categoryData?.id
    }

    private func saveTransaction() async {
        isSaving = true
        validationError = nil

        let result = await coordinator.save()

        isSaving = false

        if result.isValid {
            HapticManager.success()
            onDismiss()
        } else {
            validationError = result.errors.first?.localizedDescription
            HapticManager.error()
        }
    }
}

// MARK: - Preview

#Preview("Expense - Food") {
    let coordinator = AppCoordinator()
    TransactionAddModal(
        category: "Food",
        type: .expense,
        currency: coordinator.transactionsViewModel.appSettings.baseCurrency,
        accounts: coordinator.accountsViewModel.accounts,
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactionStore: coordinator.transactionStore,
        onDismiss: {}
    )
    .environment(coordinator)
    .environment(TimeFilterManager())
}

#Preview("Income - Salary") {
    let coordinator = AppCoordinator()
    TransactionAddModal(
        category: "Salary",
        type: .income,
        currency: coordinator.transactionsViewModel.appSettings.baseCurrency,
        accounts: coordinator.accountsViewModel.accounts,
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactionStore: coordinator.transactionStore,
        onDismiss: {}
    )
    .environment(coordinator)
    .environment(TimeFilterManager())
}
