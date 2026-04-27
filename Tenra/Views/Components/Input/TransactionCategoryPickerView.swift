//
//  TransactionCategoryPickerView.swift
//  Tenra
//
//  Category grid for creating transactions.
//  Tap a category → opens TransactionAddModal.
//  Refactored to follow Props + Callbacks pattern with zero ViewModel dependencies.
//

import SwiftUI

// MARK: - TransactionCategoryPickerView

struct TransactionCategoryPickerView: View {

    // MARK: - Coordinator

    @State private var coordinator: TransactionCategoryPickerCoordinator

    // MARK: - Environment

    @Environment(TimeFilterManager.self) private var timeFilterManager

    @Namespace private var categoryNamespace

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        timeFilterManager: TimeFilterManager
    ) {
        _coordinator = State(initialValue: TransactionCategoryPickerCoordinator(
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: transactionStore,
            timeFilterManager: timeFilterManager
        ))
    }

    // MARK: - Body

    var body: some View {
        CategoryGridView(
            categories: coordinator.categories,
            baseCurrency: coordinator.baseCurrency,
            gridColumns: nil, // Adaptive
            onCategoryTap: { category, type in
                coordinator.handleCategorySelected(category, type: type)
            },
            emptyStateAction: coordinator.handleAddCategory,
            sourceNamespace: categoryNamespace
        )
        // Push the add-transaction form into the surrounding NavigationStack instead
        // of presenting it as a sheet — this avoids the modal-on-pushed-view scroll bug
        // when the picker itself is a navigationDestination (account/category details).
        .navigationDestination(item: $coordinator.activeSelection) { selection in
            addTransactionDestination(for: selection.category, type: selection.type)
        }
        .sheet(isPresented: $coordinator.showingAddCategory) {
            categoryEditSheet
        }
    }

    // MARK: - Destinations

    private func addTransactionDestination(for category: String, type: TransactionType) -> some View {
        TransactionAddModal(
            category: category,
            type: type,
            currency: coordinator.baseCurrency,
            accounts: coordinator.accounts,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionStore: coordinator.transactionStore,
            onDismiss: coordinator.dismissModal
        )
        .environment(timeFilterManager)
        .navigationTransition(.zoom(sourceID: "\(category)_\(type.rawValue)", in: categoryNamespace))
    }

    private var categoryEditSheet: some View {
        CategoryEditView(
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            category: nil,
            type: .expense,
            onSave: coordinator.handleCategoryAdded,
            onCancel: { coordinator.showingAddCategory = false }
        )
    }
}

// MARK: - Preview

#Preview {
    let coordinator = AppCoordinator()
    let tfm = TimeFilterManager()
    TransactionCategoryPickerView(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactionStore: coordinator.transactionStore,
        timeFilterManager: tfm
    )
    .environment(tfm)
}
