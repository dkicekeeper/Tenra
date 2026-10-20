//
//  WalletMissingPaymentsView.swift
//  Tenra
//
//  From the statement review: the Apple Pay payments the Wallet action saved on the
//  statement's account that the statement does not show (WalletStatementCheck). A
//  declined payment also starts the automation, so some of them may never have been
//  charged. The rows are the History's: tap to edit, swipe to delete (with the usual
//  confirmation). Nothing is deleted on its own.
//

import SwiftUI

struct WalletMissingPaymentsView: View {
    let transactionIds: [String]
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel

    @Environment(TransactionStore.self) private var transactionStore
    @Environment(\.dismiss) private var dismiss

    /// The payments still saved: one deleted here leaves the list.
    private var payments: [Transaction] {
        // `transactionById` is @ObservationIgnored: reading the array is what re-renders
        // the list after a delete.
        _ = transactionStore.transactions.count
        return transactionIds.compactMap { transactionStore.transactionById[$0] }
    }

    var body: some View {
        List {
            Section {
                ForEach(payments) { transaction in
                    TransactionCard(
                        transaction: transaction,
                        currency: transactionStore.baseCurrency,
                        styleData: CategoryStyleHelper.cached(
                            category: transaction.category,
                            type: transaction.type,
                            customCategories: categoriesViewModel?.customCategories ?? []
                        ),
                        sourceAccount: transaction.accountId.flatMap { id in
                            accountsViewModel.accounts.first { $0.id == id }
                        },
                        viewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel,
                        balanceCoordinator: accountsViewModel.balanceCoordinator
                    )
                    .equatable()
                    .listRowInsets(EdgeInsets(
                        top: AppSpacing.sm,
                        leading: AppSpacing.lg,
                        bottom: AppSpacing.sm,
                        trailing: AppSpacing.lg
                    ))
                }
            } footer: {
                Text(String(localized: "walletMissing.footer"))
            }
        }
        .listStyle(.plain)
        // Every payment deleted: nothing is left to look at.
        .onChange(of: payments.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .navigationTitle(String(localized: "walletMissing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "button.close"), systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
}
