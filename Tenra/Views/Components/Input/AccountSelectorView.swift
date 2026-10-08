//
//  AccountSelectorView.swift
//  Tenra
//
//  Reusable account selector component with horizontal scroll
//

import SwiftUI

/// Adapter over DesignKit's `SnapCardPicker` (2.9.0): the accounts, their balances and the
/// empty and warning lines stay here; the snapping, the selection on settle and the first
/// alignment are DesignKit's.
struct AccountSelectorView: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    let warningMessage: String?
    let balanceCoordinator: BalanceCoordinator

    init(
        accounts: [Account],
        selectedAccountId: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        warningMessage: String? = nil,
        balanceCoordinator: BalanceCoordinator
    ) {
        self.accounts = accounts
        self._selectedAccountId = selectedAccountId
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.warningMessage = warningMessage
        self.balanceCoordinator = balanceCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if accounts.isEmpty {
                if let message = emptyStateMessage {
                    Text(message)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                }
            } else {
                SnapCardPicker(
                    accounts.sortedByOrder(),
                    selection: $selectedAccountId,
                    onSelectionChange: { onSelectionChange?($0) }
                ) { account, isSelected, select in
                    AccountRadioButton(
                        account: account,
                        isSelected: isSelected,
                        onTap: select,
                        balanceCoordinator: balanceCoordinator
                    )
                }
            }

            if let warning = warningMessage {
                InlineStatusText(message: warning, type: .warning)
                    .padding(.horizontal, AppSpacing.sm)
            }
        }
    }
}

// MARK: - Previews

private let previewAccounts: [Account] = [
    Account(name: "Main Card", currency: "USD", iconSource: .sfSymbol("creditcard.fill"), initialBalance: 1_234.56),
    Account(name: "Savings", currency: "EUR", iconSource: .sfSymbol("banknote.fill"), initialBalance: 8_500),
    Account(name: "Travel Wallet", currency: "GBP", iconSource: .sfSymbol("airplane"), initialBalance: 250),
    Account(name: "Cash", currency: "USD", iconSource: .sfSymbol("dollarsign.circle.fill"), initialBalance: 75.25),
    Account(name: "Investment Brokerage Long Name", currency: "USD", iconSource: .sfSymbol("chart.line.uptrend.xyaxis"), initialBalance: 42_000)
]

#Preview("Multiple — no selection") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()

    AccountSelectorView(
        accounts: previewAccounts,
        selectedAccountId: $selectedId,
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(previewAccounts)
    }
}

#Preview("Multiple — pre-selected (middle)") {
    @Previewable @State var selectedId: String? = previewAccounts[2].id
    let coordinator = AppCoordinator()

    AccountSelectorView(
        accounts: previewAccounts,
        selectedAccountId: $selectedId,
        onSelectionChange: { id in
            print("Selection changed to: \(id ?? "nil")")
        },
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(previewAccounts)
    }
}

#Preview("Single account") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()
    let single = [previewAccounts[0]]

    AccountSelectorView(
        accounts: single,
        selectedAccountId: $selectedId,
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(single)
    }
}

#Preview("Two accounts with warning") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()
    let two = Array(previewAccounts.prefix(2))

    AccountSelectorView(
        accounts: two,
        selectedAccountId: $selectedId,
        warningMessage: "Please select an account before proceeding",
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(two)
    }
}

#Preview("Empty state") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()

    AccountSelectorView(
        accounts: [],
        selectedAccountId: $selectedId,
        emptyStateMessage: "No accounts available — add one in Settings",
        balanceCoordinator: coordinator.balanceCoordinator
    )
}

#Preview("Stacked variants") {
    @Previewable @State var selectedA: String? = nil
    @Previewable @State var selectedB: String? = previewAccounts[0].id
    @Previewable @State var selectedC: String? = nil
    let coordinator = AppCoordinator()
    let two = Array(previewAccounts.prefix(2))

    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Multiple, no selection")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)
                AccountSelectorView(
                    accounts: previewAccounts,
                    selectedAccountId: $selectedA,
                    balanceCoordinator: coordinator.balanceCoordinator
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Pre-selected first")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)
                AccountSelectorView(
                    accounts: two,
                    selectedAccountId: $selectedB,
                    balanceCoordinator: coordinator.balanceCoordinator
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Empty")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)
                AccountSelectorView(
                    accounts: [],
                    selectedAccountId: $selectedC,
                    emptyStateMessage: "No accounts available",
                    balanceCoordinator: coordinator.balanceCoordinator
                )
            }
        }
        .padding(.vertical, AppSpacing.lg)
    }
    .task {
        await coordinator.balanceCoordinator.registerAccounts(previewAccounts)
    }
}
