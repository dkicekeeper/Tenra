//
//  AccountSelectorView.swift
//  AIFinanceManager
//
//  Reusable account selector component with horizontal scroll
//

import SwiftUI

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
                        .font(AppTypography.bodyLarge)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                }
            } else {
                UniversalCarousel(
                    config: .standard,
                    scrollToId: .constant(selectedAccountId)
                ) {
                    ForEach(accounts.sortedByOrder()) { account in
                        AccountRadioButton(
                            account: account,
                            isSelected: selectedAccountId == account.id,
                            onTap: {
                                selectedAccountId = account.id
                                onSelectionChange?(account.id)
                            },
                            balanceCoordinator: balanceCoordinator
                        )
                        .id(account.id)
                    }
                }
            }

            if let warning = warningMessage {
                InlineStatusText(message: warning, type: .warning)
                    .padding(.horizontal, AppSpacing.sm)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedAccountId: String? = nil
    let coordinator = AppCoordinator()

    return VStack {
        AccountSelectorView(
            accounts: [
                Account(name: "Main Account", currency: "USD", iconSource: nil, initialBalance: 1000),
                Account(name: "Savings", currency: "USD", iconSource: nil, initialBalance: 5000)
            ],
            selectedAccountId: $selectedAccountId,
            emptyStateMessage: nil,
            warningMessage: nil,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
        )

        AccountSelectorView(
            accounts: [],
            selectedAccountId: $selectedAccountId,
            emptyStateMessage: "No accounts available",
            warningMessage: nil,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
        )

        AccountSelectorView(
            accounts: [
                Account(name: "Main Account", currency: "USD", iconSource: nil, initialBalance: 1000)
            ],
            selectedAccountId: $selectedAccountId,
            emptyStateMessage: nil,
            warningMessage: "Please select an account",
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
        )
    }
    .padding()
}
