//
//  WalletReviewView.swift
//  Tenra
//
//  To review: the Apple Pay payments LogWalletPaymentIntent saved with a guessed
//  category or account (WalletCaptureStore.toReview). Opened from Settings → Wallet and
//  by a tap on a "check a payment" notification.
//
//  Tap a payment to fix it in the edit screen: saving there confirms it. "Correct" in its
//  long-press menu, or "All correct", keeps what Tenra guessed. Either way the category is
//  remembered for the merchant and the account for the card
//  (WalletPaymentRecorder.confirm), so the next payment there is not a guess.
//
//  Above the payments, the questions (DesignKit's NoticeCard): a payment that may be a
//  subscription's charge ("Merge" folds it into the planned charge, ✕ says it is not that
//  subscription), and an expense and an income of two banks merged into a transfer on a guess
//  ("Not a transfer" puts them back, ✕ keeps the transfer and remembers the names).
//

import SwiftUI

struct WalletReviewView: View {
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @Environment(TransactionStore.self) private var transactionStore
    @State private var captures = WalletCaptureStore.shared
    @State private var errorMessage: String?

    /// The payments to look at, as they are saved now. One whose transaction was deleted is
    /// skipped here and dropped from the journal by `.task`.
    private var paymentsToReview: [Transaction] {
        // `transactionById` is @ObservationIgnored: reading the observable array is what
        // re-renders the list after an edit made from it.
        _ = transactionStore.transactions.count
        return captures.toReview
            .filter { !$0.isReviewed && !$0.guesses.isEmpty && $0.ownTransfer == nil }
            .compactMap { transactionStore.transactionById[$0.id] }
    }

    /// A payment and the subscription whose planned charge it may be.
    private struct SubscriptionQuestion: Identifiable {
        let capture: WalletCaptureStore.Capture
        let transaction: Transaction
        let series: RecurringSeries
        var id: String { capture.id }
    }

    private var subscriptionQuestions: [SubscriptionQuestion] {
        _ = transactionStore.transactions.count
        return captures.toReview.compactMap { capture in
            guard let seriesId = capture.subscriptionSuggestion,
                  let series = transactionStore.recurringSeries.first(where: { $0.id == seriesId }),
                  let transaction = transactionStore.transactionById[capture.id],
                  transaction.recurringSeriesId == nil
            else { return nil }
            return SubscriptionQuestion(capture: capture, transaction: transaction, series: series)
        }
    }

    /// Transfers merged from two banks' notifications on the amount and the time alone.
    private var transferQuestions: [Transaction] {
        _ = transactionStore.transactions.count
        return captures.toReview
            .filter { !$0.isReviewed && $0.ownTransfer != nil }
            .compactMap { transactionStore.transactionById[$0.id] }
    }

    /// Before the full load the index holds part of the history only: a payment to review may
    /// be missing from it (the list would flash empty), and a confirm would read its
    /// subcategories before they are loaded and remember none. Placeholders until then.
    private var isWaitingForHistory: Bool {
        !captures.toReview.isEmpty && !transactionStore.hasCompletedInitialLoad
    }

    var body: some View {
        let transactions = paymentsToReview
        let subscriptionQuestions = subscriptionQuestions
        let transferQuestions = transferQuestions
        let isEmpty = transactions.isEmpty && subscriptionQuestions.isEmpty && transferQuestions.isEmpty
        let isWaiting = isWaitingForHistory
        Group {
            if isWaiting {
                ScrollView {
                    FormSection {
                        ForEach(0..<min(captures.toReview.count, 6), id: \.self) { _ in
                            SkeletonRow()
                                .rowDividerInset(AppIconSize.xxl + AppSpacing.md)
                        }
                    }
                    .screenPadding()
                }
                .transition(.opacity)
            } else if isEmpty {
                EmptyState(
                    icon: "checkmark.circle",
                    title: String(localized: "walletReview.emptyTitle"),
                    description: String(localized: "walletReview.emptyMessage")
                )
                .transition(.opacity)
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        if let errorMessage {
                            MessageBanner(message: errorMessage, type: .error)
                        }
                        ForEach(transferQuestions) { transfer in
                            transferNotice(for: transfer)
                        }
                        ForEach(subscriptionQuestions) { question in
                            subscriptionNotice(for: question)
                        }
                        if !transactions.isEmpty {
                            FormSection(footer: String(localized: "walletReview.footer")) {
                                ForEach(transactions) { transaction in
                                    card(for: transaction)
                                }
                            }
                        }
                    }
                    .screenPadding()
                }
                .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: isEmpty)
        .animation(AppAnimation.gentleSpring, value: isWaiting)
        .navigationTitle(String(localized: "walletReview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isWaiting, !transactions.isEmpty || !transferQuestions.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "walletReview.confirmAll")) {
                        HapticManager.success()
                        (transferQuestions + transactions).forEach(confirm)
                    }
                }
            }
        }
        // Again once the full load lands, if the list opened before it.
        .task(id: isWaiting) {
            // Before the full load the index is partial, and every capture would look deleted.
            guard transactionStore.hasCompletedInitialLoad else { return }
            captures.removeCaptures(notIn: Set(transactionStore.transactionById.keys))
            // A suggestion nobody can answer any more (its subscription deleted, the payment
            // linked elsewhere) would keep the payment counted as waiting.
            let shown = Set(subscriptionQuestions.map(\.id))
            for capture in captures.toReview where capture.subscriptionSuggestion != nil && !shown.contains(capture.id) {
                captures.clearSubscriptionSuggestion(transactionId: capture.id)
            }
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
            balanceCoordinator: accountsViewModel.balanceCoordinator,
            menuAction: TransactionCard.MenuAction(
                title: String(localized: "walletReview.confirm"),
                systemImage: "checkmark"
            ) {
                HapticManager.success()
                confirm(transaction)
            }
        )
        .equatable()
        // The divider under the row's text: past its 44 pt icon and the space after it.
        .rowDividerInset(AppIconSize.Tile.sm + AppSpacing.md)
        .accessibilityAction(named: Text(String(localized: "walletReview.confirm"))) {
            confirm(transaction)
        }
        .accessibilityIdentifier("walletReview.payment")
    }

    // MARK: - Questions

    /// "Freedom → Kaspi Gold · 100 000 ₸": ✕ keeps the transfer, "Not a transfer" puts the
    /// expense and the income back.
    private func transferNotice(for transfer: Transaction) -> some View {
        let from = accountsViewModel.accounts.first { $0.id == transfer.accountId }?.name ?? ""
        let to = accountsViewModel.accounts.first { $0.id == transfer.targetAccountId }?.name ?? ""
        let amount = Formatting.formatCurrencySmart(transfer.amount, currency: transfer.currency)
        return NoticeCard(
            title: String(localized: "walletReview.ownTransfer.title"),
            message: "\(from) → \(to) · \(amount)",
            actionTitle: String(localized: "walletReview.ownTransfer.split"),
            actionSystemImage: "arrow.uturn.backward",
            action: { split(transfer) },
            hideLabel: String(localized: "walletReview.confirm"),
            onHide: {
                HapticManager.success()
                confirm(transfer)
            }
        ) {
            Icon(source: .sfSymbol("arrow.left.arrow.right"), size: NoticeCardMetrics.leadingSize)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("walletReview.ownTransfer")
    }

    /// "Looks like Netflix / NETFLIX.COM · 5 200 ₸ · 7 Nov": "Merge" folds the payment into the
    /// planned charge, ✕ says it is not that subscription (never asked again for the merchant).
    private func subscriptionNotice(for question: SubscriptionQuestion) -> some View {
        let transaction = question.transaction
        let merchant = question.capture.payment.merchant.isEmpty
            ? transaction.description
            : MerchantName.displayName(question.capture.payment.merchant)
        let amount = Formatting.formatCurrencySmart(transaction.amount, currency: transaction.currency)
        let day = DateFormatters.dateFormatter.date(from: transaction.date)
            .map(DateFormatters.displayDateOmittingCurrentYear) ?? transaction.date
        return NoticeCard(
            title: String(format: String(localized: "walletReview.subscription.title"), question.series.description),
            message: "\(merchant) · \(amount) · \(day)",
            actionTitle: String(localized: "walletReview.subscription.merge"),
            actionSystemImage: "link",
            action: { merge(question) },
            hideLabel: String(localized: "walletReview.subscription.notIt"),
            onHide: { dismiss(question) }
        ) {
            Icon(source: question.series.iconSource ?? .sfSymbol("repeat"), size: NoticeCardMetrics.leadingSize)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("walletReview.subscription")
    }

    private func merge(_ question: SubscriptionQuestion) {
        Task {
            do {
                try await SubscriptionChargeLinker.link(
                    question.transaction,
                    to: question.series,
                    merchant: question.capture.payment.merchant.isEmpty ? nil : question.capture.payment.merchant,
                    store: transactionStore
                )
                HapticManager.success()
            } catch {
                HapticManager.error()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func dismiss(_ question: SubscriptionQuestion) {
        let merchant = question.capture.payment.merchant.isEmpty
            ? question.transaction.description
            : question.capture.payment.merchant
        SubscriptionMerchantMemory.shared.dismiss(seriesId: question.series.id, forMerchant: merchant)
        captures.clearSubscriptionSuggestion(transactionId: question.capture.id)
        if captures.capture(forTransactionId: question.capture.id)?.needsReview != true {
            WalletReviewNotifier.removeDelivered(transactionId: question.capture.id)
        }
    }

    private func split(_ transfer: Transaction) {
        Task {
            do {
                try await OwnTransferMerger.split(transferId: transfer.id, store: transactionStore)
                HapticManager.success()
            } catch {
                HapticManager.error()
                errorMessage = error.localizedDescription
            }
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
