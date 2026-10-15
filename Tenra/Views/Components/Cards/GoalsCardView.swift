//
//  GoalsCardView.swift
//  Tenra
//
//  The Goals card in Finances (docs/domains/goals-and-debts.md): everything saved towards the
//  goals in the base currency, how many there are, and their icons. Goals are free.
//

import SwiftUI

struct GoalsCardView: View {
    let goalStore: GoalStore
    let baseCurrency: String
    /// The FX refresh (TransactionStore.currencyRatesVersion): goals in other currencies are
    /// converted with the cached rates, so the total is drawn again when they change.
    let ratesVersion: Int

    var body: some View {
        let goals = goalStore.goals
        FinanceCard(
            title: String(localized: "finances.goals.title"),
            isEmpty: goals.isEmpty,
            emptyTitle: String(localized: "finances.goals.empty"),
            subtitle: String(format: NSLocalizedString("finances.goals.count", comment: "Count with plural forms in Localizable.stringsdict"), goals.count)
        ) {
            RedactableAmount(amount: goalStore.totalSaved(in: baseCurrency), currency: baseCurrency, isLoading: !goalStore.isLoaded)
        } trailing: {
            PackedCircleIcons(
                items: goals.map { goal in
                    PackedCircleItem(
                        id: goal.id,
                        iconSource: goal.iconSource ?? SavingsGoal.defaultIcon,
                        amount: max(goalStore.saved(for: goal), 0)
                    )
                },
                // App icons in a pocket (DesignKit 4.4.0), centred in the card (4.5.0).
                style: .shelf
            )
        }
    }
}

#Preview("Goals Card") {
    let store = GoalStore(repository: nil)
    GoalsCardView(goalStore: store, baseCurrency: "KZT", ratesVersion: 0)
        .screenPadding()
        .task {
            await store.add(SavingsGoal(name: "Car", targetAmount: 3_000_000, currency: "KZT", contributions: [GoalContribution(amount: 1_200_000, date: Date())]))
            await store.add(SavingsGoal(name: "Vacation", iconSource: .sfSymbol("airplane"), targetAmount: 600_000, currency: "KZT"))
        }
}
