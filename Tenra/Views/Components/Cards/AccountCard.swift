//
//  AccountCard.swift
//  AIFinanceManager
//
//  Reusable account card component
//

import SwiftUI

struct AccountCard: View {
    let account: Account
    let balanceCoordinator: BalanceCoordinator
    var namespace: Namespace.ID

    private var balance: Double {
        balanceCoordinator.balances[account.id] ?? 0
    }

    var body: some View {
        NavigationLink(value: account) {
            HStack(spacing: AppSpacing.sm) {
                IconView(source: account.iconSource, size: AppIconSize.xl)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                        .foregroundStyle(.primary)

                    FormattedAmountText(
                        amount: balance,
                        currency: account.currency,
                        fontSize: AppTypography.bodySmall,
                        fontWeight: .semibold,
                        color: .primary
                    )
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
            .glassEffectID("account-card-\(account.id)", in: namespace)
        }
        .buttonStyle(.bounce)
        .matchedTransitionSource(id: account.id, in: namespace)
        .accessibilityLabel(String(format: String(localized: "accessibility.accountCard.label"), account.name, Formatting.formatCurrency(balance, currency: account.currency)))
        .accessibilityHint(String(localized: "accessibility.accountCard.hint"))
    }
}

#Preview("Account Card") {
    @Previewable @Namespace var ns
    let coordinator = AppCoordinator()
    NavigationStack {
        AccountCard(
            account: Account(name: "Main Account", currency: "USD", iconSource: nil, initialBalance: 1000),
            balanceCoordinator: coordinator.balanceCoordinator,
            namespace: ns
        )
        .padding()
    }
}
