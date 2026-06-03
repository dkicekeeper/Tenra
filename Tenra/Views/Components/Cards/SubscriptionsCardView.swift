//
//  SubscriptionsCardView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    // Fix #7: Double instead of Decimal — avoids NSDecimalNumber round-trip at the use site.
    @State private var totalAmount: Double = 0
    @State private var isLoadingTotal: Bool = false
    /// Subscription amounts converted to base currency for PackedCircleIconsView sizing.
    @State private var convertedAmounts: [String: Double] = [:]

    private var subscriptions: [RecurringSeries] {
        transactionStore.activeSubscriptions
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// Combined key driving .task(id:) — restarts automatically when count or currency changes.
    private var refreshID: String {
        "\(subscriptions.count)-\(baseCurrency)"
    }

    var body: some View {
        FinanceCard(
            title: String(localized: "subscriptions.title"),
            isEmpty: subscriptions.isEmpty,
            emptyTitle: String(localized: "emptyState.noActiveSubscriptions"),
            subtitle: String(format: String(localized: "subscriptions.activeCount"), subscriptions.count)
        ) {
            RedactableAmount(amount: totalAmount, currency: baseCurrency, isLoading: isLoadingTotal)
        } trailing: {
            PackedCircleIconsView(
                items: subscriptions.map { sub in
                    PackedCircleItem(
                        id: sub.id,
                        iconSource: sub.iconSource,
                        amount: convertedAmounts[sub.id] ?? (sub.amount as NSDecimalNumber).doubleValue
                    )
                }
            )
        }
        // Fix #3: replaced two separate `onChange + unstructured Task {}` blocks with a single
        // `.task(id: refreshID)`. SwiftUI automatically cancels and restarts this task whenever
        // `refreshID` changes (subscriptions count or base currency), and cancels it on view
        // removal — no task leaks on sheet dismiss.
        .task(id: refreshID) {
            await refreshTotal()
        }
    }

    /// Calculate total subscription amount in base currency.
    private func refreshTotal() async {
        // Show the redacted placeholder only on the very first load — refreshing
        // an already-displayed value over the placeholder is jarring and reads as a
        // flicker on every recurring-series mutation.
        let isFirstLoad = totalAmount == 0
        if isFirstLoad { isLoadingTotal = true }

        let baseCur = baseCurrency
        // Snapshot subscription scalars on MainActor so the TaskGroup body works
        // with Sendable value types only — avoids capturing RecurringSeries refs.
        let subTuples: [(id: String, currency: String, raw: Double)] = subscriptions.map {
            (id: $0.id, currency: $0.currency, raw: ($0.amount as NSDecimalNumber).doubleValue)
        }

        // Compute total and per-subscription conversions in parallel. The total query
        // hits CurrencyConverter once; the per-sub loop did N sequential awaits before.
        async let totalResult = transactionStore.calculateSubscriptionsTotalInCurrency(baseCur)
        async let amountsByID: [String: Double] = withTaskGroup(of: (String, Double).self) { group in
            for sub in subTuples {
                group.addTask {
                    if sub.currency == baseCur { return (sub.id, sub.raw) }
                    let converted = await CurrencyConverter.convert(
                        amount: sub.raw, from: sub.currency, to: baseCur
                    )
                    return (sub.id, converted ?? sub.raw)
                }
            }
            var dict: [String: Double] = [:]
            dict.reserveCapacity(subTuples.count)
            for await (id, amount) in group {
                dict[id] = amount
            }
            return dict
        }

        let result = await totalResult
        let amounts = await amountsByID

        totalAmount = (result.total as NSDecimalNumber).doubleValue
        convertedAmounts = amounts
        isLoadingTotal = false
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsCardView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .screenPadding()
}
