//
//  DebtsCardView.swift
//  Tenra
//
//  The Debts card in Finances (docs/domains/goals-and-debts.md): what others owe the person
//  and what the person owes, in the base currency (RedactableAmount: hidden with the other
//  amounts, a skeleton until the store loads), how many debts are open, and the open debts on
//  the shelf like every Finances card (green arrows owed to the person, red ones owed by them,
//  sized by what is left in the base currency). Debts are a Tenra Pro feature; the card shows
//  them either way, adding one goes through the paywall.
//

import SwiftUI

struct DebtsCardView: View {
    let debtStore: DebtStore
    let baseCurrency: String
    /// The FX refresh (TransactionStore.currencyRatesVersion): debts in other currencies are
    /// converted with the cached rates, so the totals are drawn again when they change.
    let ratesVersion: Int

    var body: some View {
        let open = debtStore.open(.owedToMe) + debtStore.open(.iOwe)
        let openCount = open.count
        FinanceCard(
            title: String(localized: "finances.debts.title"),
            isEmpty: debtStore.debts.isEmpty,
            emptyTitle: String(localized: "finances.debts.empty"),
            subtitle: String(format: NSLocalizedString("finances.debts.count", comment: "Count with plural forms in Localizable.stringsdict"), openCount)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                totalLine(String(localized: "finances.debts.owedToMe"), amount: debtStore.total(.owedToMe, in: baseCurrency))
                totalLine(String(localized: "finances.debts.iOwe"), amount: debtStore.total(.iOwe, in: baseCurrency))
            }
        } trailing: {
            PackedCircleIcons(
                items: open.map { debt in
                    PackedCircleItem(
                        id: debt.id,
                        iconSource: debt.iconSource,
                        amount: CurrencyConverter.convertSync(amount: debt.remaining, from: debt.currency, to: baseCurrency) ?? debt.remaining,
                        tint: debt.direction == .owedToMe ? AppColors.income : AppColors.destructive
                    )
                },
                style: .shelf
            )
        }
    }

    private func totalLine(_ title: String, amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            RedactableAmount(amount: amount, currency: baseCurrency, isLoading: !debtStore.isLoaded, fontSize: AppTypography.h4)
        }
    }
}

#Preview("Debts Card") {
    let store = DebtStore(repository: nil)
    DebtsCardView(debtStore: store, baseCurrency: "KZT", ratesVersion: 0)
        .screenPadding()
        .task {
            await store.add(PersonalDebt(direction: .owedToMe, person: "Askhat", amount: 50_000, currency: "KZT"))
            await store.add(PersonalDebt(direction: .iOwe, person: "Mum", amount: 20_000, currency: "KZT"))
        }
}
