//
//  DebtsCardView.swift
//  Tenra
//
//  The Debts card in Finances (docs/domains/goals-and-debts.md): what others owe the person
//  and what the person owes, in the base currency, and how many debts are open. Debts are a
//  Tenra Pro feature; the card shows them either way, adding one goes through the paywall.
//

import SwiftUI

struct DebtsCardView: View {
    let debtStore: DebtStore
    let baseCurrency: String
    /// The FX refresh (TransactionStore.currencyRatesVersion): debts in other currencies are
    /// converted with the cached rates, so the totals are drawn again when they change.
    let ratesVersion: Int

    var body: some View {
        let openCount = debtStore.open(.owedToMe).count + debtStore.open(.iOwe).count
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
            EmptyView()
        }
    }

    private func totalLine(_ title: String, amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            FormattedAmountText(
                amount: amount,
                currency: baseCurrency,
                fontSize: AppTypography.h4,
                fontWeight: .semibold,
                color: AppColors.textPrimary
            )
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
