//
//  AccountRadioButton.swift
//  Tenra
//
//  Account option of a picker. Adapter over DesignKit's `SelectableBalanceCard`: reading the
//  balance from BalanceCoordinator stays here.
//

import SwiftUI

struct AccountRadioButton: View {
    let account: Account
    let isSelected: Bool
    let onTap: () -> Void
    let balanceCoordinator: BalanceCoordinator
    
    private var balance: Double {
        balanceCoordinator.balances[account.id] ?? 0
    }
    
    var body: some View {
        SelectableBalanceCard(
            iconSource: account.iconSource,
            title: account.name,
            amount: balance,
            currency: account.currency,
            isSelected: isSelected,
            action: onTap
        )
    }
}

#Preview {
    let coordinator = AppCoordinator()

    HStack {
        AccountRadioButton(
            account: Account(name: "Main Account", currency: "USD", iconSource: nil, initialBalance: 1000),
            isSelected: false,
            onTap: {},
            balanceCoordinator: coordinator.balanceCoordinator
        )
        AccountRadioButton(
            account: Account(name: "Savings", currency: "USD", iconSource: nil, initialBalance: 5000),
            isSelected: true,
            onTap: {},
            balanceCoordinator: coordinator.balanceCoordinator
        )
    }
    .padding()
}
