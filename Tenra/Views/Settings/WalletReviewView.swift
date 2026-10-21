//
//  WalletReviewView.swift
//  Tenra
//
//  To review: the Apple Pay payments LogWalletPaymentIntent saved with a guessed
//  category or account (WalletCaptureStore.toReview). Opened from Settings → Wallet and
//  by a tap on a "check a payment" notification.
//
//  Tap a payment to fix it in the edit screen: saving there confirms it. Swipe right,
//  or "All correct", to keep what Tenra guessed. Either way the category is
//  remembered for the merchant and the account for the card
//  (WalletPaymentRecorder.confirm), so the next payment there is not a guess.
//

import SwiftUI

struct WalletReviewView: View {
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @Environment(TransactionStore.self) private var transactionStore
    @State private var captures = WalletCaptureStore.shared

    /// The payments to look at, as they are saved now. One whose transaction was deleted is
    /// skipped here and dropped from the journal by `.task`.
    private var paymentsToReview: [Transaction] {
        // `transactionById` is @ObservationIgnored: reading the observable array is what
        // re-renders the list after an edit made from it.
        _ = transactionStore.transactions.count
        return captures.toReview.compactMap { transactionStore.transactionById[$0.id] }
    }

    /// Before the full load the index holds part of the history only: a payment to review may
    /// be missing from it (the list would flash empty), and a confirm would read its
    /// subcategories before they are loaded and remember none. Placeholders until then.
    private var isWaitingForHistory: Bool {
        !captures.toReview.isEmpty && !transactionStore.hasCompletedInitialLoad
    }

    var body: some View {
        let transactions = paymentsToReview
        let isWaiting = isWaitingForHistory
        Group {
            if isWaiting {
                List {
                    ForEach(0..<min(captures.toReview.count, 6), id: \.self) { _ in
                        SkeletonRow()
                    }
                }
                .listStyle(.plain)
                .transition(.opacity)
            } else if transactions.isEmpty {
                EmptyState(
                    icon: "checkmark.circle",
                    title: String(localized: "walletReview.emptyTitle"),
                    description: String(localized: "walletReview.emptyMessage")
                )
                .transition(.opacity)
            } else {
                List {
                    Section {
                        ForEach(transactions) { transaction in
                            card(for: transaction)
                        }
                    } footer: {
                        Text(String(localized: "walletReview.footer"))
                    }
                }
                .listStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: transactions.isEmpty)
        .animation(AppAnimation.gentleSpring, value: isWaiting)
        .navigationTitle(String(localized: "walletReview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isWaiting, !transactions.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "walletReview.confirmAll")) {
                        HapticManager.success()
                        transactions.forEach(confirm)
                    }
                }
            }
        }
        // Again once the full load lands, if the list opened before it.
        .task(id: isWaiting) {
            // Before the full load the index is partial, and every capture would look deleted.
            guard transactionStore.hasCompletedInitialLoad else { return }
            captures.removeCaptures(notIn: Set(transactionStore.transactionById.keys))
        }
    }

    // MARK: - Row

    private func card(for transaction: Transaction) -> some View {
        TransactionCard(
            transaction: transaction,
            currency: transactionStore.baseCurrency,
            styleData: CategoryStyleHelper.cached(
                category: transaction.category,
                type: transaction.type,
                customCategories: categoriesViewModel.customCategories
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
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                HapticManager.success()
                confirm(transaction)
            } label: {
                Label(String(localized: "walletReview.confirm"), systemImage: "checkmark")
            }
            .tint(AppColors.success)
        }
        .accessibilityAction(named: Text(String(localized: "walletReview.confirm"))) {
            confirm(transaction)
        }
    }

    /// Keeps the payment as it is saved now, and remembers it for its merchant and card.
    private func confirm(_ transaction: Transaction) {
        WalletPaymentRecorder.confirm(
            transaction,
            subcategoryIds: categoriesViewModel.getSubcategoriesForTransaction(transaction.id).map(\.id),
            categories: categoriesViewModel.customCategories
        )
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        WalletReviewView(
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
    }
    .environment(coordinator.transactionStore)
}
