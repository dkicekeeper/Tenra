//
//  DailyAllowanceLink.swift
//  Tenra
//
//  "For today" on Analytics, under the period's stat cards: how much can go out a day until the
//  next income (DailyAllowance, Ten's forecast_balance), a link to how it is reached
//  (DailyAllowanceDetailView). Self-contained: reads the coordinator and recomputes whenever an
//  input changes. Hidden without an everyday account to spend from.
//

import SwiftUI

struct DailyAllowanceLink: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var value: DailyAllowance.Value?

    private var store: TransactionStore { coordinator.transactionStore }

    // Everything "For today" depends on (CLAUDE.md, red flag 12): the history, the accounts,
    // the subscriptions and other series before the next income, the income categories that
    // find that income, the rates, the base currency and the day.
    private struct Trigger: Equatable {
        let txVersion: Int
        let accountsVersion: Int
        let series: [RecurringSeries]
        let categoriesVersion: Int
        let ratesVersion: Int
        let baseCurrency: String
        let day: Date
        let isFullyInitialized: Bool
    }

    private var trigger: Trigger {
        // Both versions are @ObservationIgnored: touch the observable arrays so `body` re-runs.
        _ = store.transactions.count
        _ = store.accounts.count
        return Trigger(
            txVersion: store.mutationVersion,
            accountsVersion: store.accountsMutationVersion,
            series: store.recurringSeries,
            categoriesVersion: store.categoriesMutationVersion,
            ratesVersion: store.currencyRatesVersion,
            baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
            day: Calendar.current.startOfDay(for: Date()),
            isFullyInitialized: coordinator.isFullyInitialized
        )
    }

    var body: some View {
        Group {
            if let value {
                NavigationLink {
                    DailyAllowanceDetailView(value: value)
                } label: {
                    DailyAllowanceCard(
                        amount: value.amount,
                        currency: value.currency,
                        until: value.income,
                        setAside: value.setAside,
                        isLoading: false
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bounce)
                .accessibilityIdentifier("insights.allowance")
                .transition(.opacity)
            }
        }
        .task(id: trigger) {
            guard coordinator.isFullyInitialized, !store.isImporting else { return }
            let computed = await DailyAllowance.value(store: store)
            guard !Task.isCancelled else { return }
            withAnimation(AppAnimation.smooth) { value = computed }
        }
    }
}
