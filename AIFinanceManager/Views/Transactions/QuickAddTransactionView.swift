//
//  QuickAddTransactionView.swift
//  AIFinanceManager
//
//  Quick add transaction view with category grid.
//  Refactored to follow Props + Callbacks pattern with zero ViewModel dependencies.
//

import SwiftUI

// MARK: - QuickAddTransactionView

struct QuickAddTransactionView: View {

    // MARK: - Coordinator

    @State private var coordinator: QuickAddCoordinator

    // MARK: - Environment

    @Environment(TimeFilterManager.self) private var timeFilterManager

    @Namespace private var categoryNamespace

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        // Fix #4: accept the real TimeFilterManager so QuickAddCoordinator computes
        // categories with the correct filter on the very first body evaluation.
        // Previously a dummy TimeFilterManager() was used and replaced in onAppear,
        // causing two category-computation passes with different filter values.
        timeFilterManager: TimeFilterManager
    ) {
        _coordinator = State(initialValue: QuickAddCoordinator(
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
        .sheet(item: $coordinator.activeSelection) { selection in
            addTransactionSheet(for: selection.category, type: selection.type)
        }
        .sheet(isPresented: $coordinator.showingAddCategory) {
            categoryEditSheet
        }
    }

    // MARK: - Sheets

    private func addTransactionSheet(for category: String, type: TransactionType) -> some View {
        AddTransactionModal(
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
    QuickAddTransactionView(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactionStore: coordinator.transactionStore,
        timeFilterManager: tfm
    )
    .environment(tfm)
}
