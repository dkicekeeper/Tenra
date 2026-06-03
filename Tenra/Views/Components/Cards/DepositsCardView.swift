//
//  DepositsCardView.swift
//  Tenra
//
//  Summary card showing total balance across deposit accounts. Deposits used to
//  live inside AccountsCardView; they now have their own card and management
//  screen in Finances. Accounts excluded from balance are omitted.
//

import SwiftUI

struct DepositsCardView: View {
    let accountsViewModel: AccountsViewModel
    let balanceCoordinator: BalanceCoordinator
    let transactionsViewModel: TransactionsViewModel

    @State private var totalAmount: Double = 0
    @State private var isLoadingTotal: Bool = false

    private var deposits: [Account] {
        accountsViewModel.depositAccounts.filter { $0.includeInBalance }
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// Drives `.task(id:)` — restarts when the deposit list, currency, or observed
    /// balances change. Mirrors AccountsCardView's reactivity contract.
    private var refreshID: String {
        let snapshot = deposits
            .map { "\($0.id):\(balanceCoordinator.balances[$0.id] ?? 0)" }
            .joined(separator: ",")
        return "\(baseCurrency)|\(snapshot)"
    }

    var body: some View {
        FinanceCard(
            title: String(localized: "finances.deposits.title", defaultValue: "Deposits"),
            isEmpty: deposits.isEmpty,
            emptyTitle: String(localized: "finances.deposits.empty", defaultValue: "No deposits"),
            subtitle: String(format: String(localized: "finances.deposits.count", defaultValue: "%lld deposits"), deposits.count)
        ) {
            RedactableAmount(amount: totalAmount, currency: baseCurrency, isLoading: isLoadingTotal)
        } trailing: {
            depositIcons
        }
        .task(id: refreshID) {
            await refreshTotal()
        }
    }

    // MARK: - Icons

    private var depositIcons: some View {
        let balancesById = balanceCoordinator.balances
        return PackedCircleIconsView(
            items: deposits.map { deposit in
                PackedCircleItem(
                    id: deposit.id,
                    iconSource: deposit.iconSource,
                    amount: max(balancesById[deposit.id] ?? 0, 0)
                )
            }
        )
    }

    // MARK: - Total Calculation

    /// Sums deposit balances converted to base currency. Mirrors AccountsCardView's
    /// parallel task-group FX pattern.
    private func refreshTotal() async {
        let isFirstLoad = totalAmount == 0
        if isFirstLoad { isLoadingTotal = true }

        let baseCur = baseCurrency
        let balancesById = balanceCoordinator.balances
        let tuples: [(id: String, currency: String, balance: Double)] = deposits.map {
            (id: $0.id, currency: $0.currency, balance: balancesById[$0.id] ?? 0)
        }

        let total = await withTaskGroup(of: Double.self) { group in
            for tuple in tuples {
                group.addTask {
                    if tuple.currency == baseCur { return tuple.balance }
                    let converted = await CurrencyConverter.convert(
                        amount: tuple.balance, from: tuple.currency, to: baseCur
                    )
                    return converted ?? tuple.balance
                }
            }
            var sum: Double = 0
            for await value in group { sum += value }
            return sum
        }

        totalAmount = total
        isLoadingTotal = false
    }
}

// MARK: - Preview

#Preview("Deposits Card") {
    let coordinator = AppCoordinator()
    DepositsCardView(
        accountsViewModel: coordinator.accountsViewModel,
        balanceCoordinator: coordinator.balanceCoordinator,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .screenPadding()
}
