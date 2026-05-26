//
//  AccountRadioButton.swift
//  Tenra
//
//  Reusable account radio button component
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
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                IconView(source: account.iconSource, size: AppIconSize.xxl)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                    
                    FormattedAmountText(
                        amount: balance,
                        currency: account.currency,
                        fontSize: AppTypography.body,
                        fontWeight: .semibold,
                        color: .primary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.lg)
            .cardStyle()
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .stroke(AppColors.accent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
                    .animation(AppAnimation.gentleSpring, value: isSelected)
            }
        }
        .buttonStyle(.bounce)
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
