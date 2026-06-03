//
//  AccountsCardView.swift
//  Tenra
//
//  Summary card showing total balance across regular accounts.
//  Deposits live in DepositsCardView and loans in LoansCardView — both excluded
//  here. Accounts the user excluded from balance are also omitted.
//

import SwiftUI

struct AccountsCardView: View {
    let accountsViewModel: AccountsViewModel
    let balanceCoordinator: BalanceCoordinator
    let transactionsViewModel: TransactionsViewModel

    @State private var totalAmount: Double = 0
    @State private var isLoadingTotal: Bool = false

    private var accounts: [Account] {
        // Deposits moved to DepositsCardView; loans live in LoansCardView.
        // Accounts excluded from balance are omitted from the summary total,
        // count, and icon cluster (they remain in the full accounts list).
        accountsViewModel.regularAccounts.filter { $0.includeInBalance }
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// Drives `.task(id:)` — restarts when the underlying account list, currency, or
    /// observed balances change. Reading `balanceCoordinator.balances` here keeps the
    /// total reactive to balance writes (`accountsMutationVersion` only fires on
    /// add/remove/reorder, not on balance updates).
    private var refreshID: String {
        let snapshot = accounts
            .map { "\($0.id):\(balanceCoordinator.balances[$0.id] ?? 0)" }
            .joined(separator: ",")
        return "\(baseCurrency)|\(snapshot)"
    }

    var body: some View {
        FinanceCard(
            title: String(localized: "finances.accounts.title"),
            isEmpty: accounts.isEmpty,
            emptyTitle: String(localized: "finances.accounts.empty"),
            subtitle: String(format: String(localized: "finances.accounts.count"), accounts.count)
        ) {
            RedactableAmount(amount: totalAmount, currency: baseCurrency, isLoading: isLoadingTotal)
        } trailing: {
            accountIcons
        }
        .task(id: refreshID) {
            await refreshTotal()
        }
    }

    // MARK: - Icons

    private var accountIcons: some View {
        let balancesById = balanceCoordinator.balances
        return PackedCircleIconsView(
            items: accounts.map { account in
                PackedCircleItem(
                    id: account.id,
                    iconSource: account.iconSource,
                    amount: max(balancesById[account.id] ?? 0, 0)
                )
            }
        )
    }

    // MARK: - Total Calculation

    /// Sums account balances converted to base currency. Mirrors the parallel
    /// task-group pattern used in SubscriptionsCardView so per-account FX lookups
    /// run concurrently rather than sequentially.
    private func refreshTotal() async {
        let isFirstLoad = totalAmount == 0
        if isFirstLoad { isLoadingTotal = true }

        let baseCur = baseCurrency
        let balancesById = balanceCoordinator.balances
        let tuples: [(id: String, currency: String, balance: Double)] = accounts.map {
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

#Preview("Accounts Card") {
    let coordinator = AppCoordinator()
    AccountsCardView(
        accountsViewModel: coordinator.accountsViewModel,
        balanceCoordinator: coordinator.balanceCoordinator,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .screenPadding()
}
