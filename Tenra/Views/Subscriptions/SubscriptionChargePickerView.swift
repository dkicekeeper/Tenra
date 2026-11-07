//
//  SubscriptionChargePickerView.swift
//  Tenra
//
//  "This is a subscription…" in an expense's edit screen (the repeat menu): the person picks
//  the subscription this charge belongs to. The planned charge of its period takes the
//  expense's amount, date and account, and the expense goes (SubscriptionChargeLinker); with no
//  planned charge near, the expense is linked as it is. The merchant is remembered, so its next
//  charge merges on its own. The subscriptions closest by amount come first.
//  docs/domains/recurring.md §Real charges.
//

import SwiftUI

struct SubscriptionChargePickerView: View {
    let charge: Transaction
    let transactionStore: TransactionStore
    let baseCurrency: String
    /// After the link, before the picker closes: the edit screen closes once it has (the expense
    /// may have merged into the planned charge). The saved expense is linked, not unsaved edits.
    let onLinked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLinking = false
    @State private var errorMessage: String?

    /// Subscriptions first, by how close their amount is to the charge's (in the base currency).
    private var subscriptions: [RecurringSeries] {
        let charged = CurrencyConverter.convertSync(amount: charge.amount, from: charge.currency, to: baseCurrency) ?? charge.amount
        func gap(_ series: RecurringSeries) -> Double {
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let planned = CurrencyConverter.convertSync(amount: amount, from: series.currency, to: baseCurrency) ?? amount
            return abs(planned - charged)
        }
        return transactionStore.subscriptions.sorted { gap($0) < gap($1) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactionStore.subscriptions.isEmpty {
                    EmptyState(
                        icon: "repeat",
                        title: String(localized: "transaction.linkSubscription.emptyTitle"),
                        description: String(localized: "transaction.linkSubscription.emptyMessage")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            if let errorMessage {
                                MessageBanner(message: errorMessage, type: .error)
                            }
                            CardList(subscriptions, layout: .stack, onOpen: link) { subscription in
                                SubscriptionCard(
                                    subscription: subscription,
                                    nextChargeDate: transactionStore.nextChargeDate(for: subscription.id),
                                    baseCurrency: baseCurrency
                                )
                                .equatable()
                            }
                            .disabled(isLinking)
                            Text(String(localized: "transaction.linkSubscription.footer"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.Text.secondary)
                                .padding(.horizontal, AppSpacing.lg)
                        }
                        .screenPadding()
                    }
                }
            }
            .navigationTitle(String(localized: "transaction.linkSubscription.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "button.close"))
                }
            }
        }
    }

    private func link(_ subscription: RecurringSeries) {
        guard !isLinking else { return }
        isLinking = true
        Task {
            do {
                try await SubscriptionChargeLinker.link(charge, to: subscription, store: transactionStore)
                HapticManager.success()
                onLinked()
                dismiss()
            } catch {
                HapticManager.error()
                errorMessage = error.localizedDescription
                isLinking = false
            }
        }
    }
}
