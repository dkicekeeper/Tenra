//
//  AccountFilterView.swift
//  AIFinanceManager
//
//  Account filter sheet for HistoryView
//

import SwiftUI

struct AccountFilterView: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let balanceCoordinator: BalanceCoordinator?

    @Environment(\.dismiss) var dismiss

    private var sortedAccounts: [Account] {
        accounts.sortedByOrder()
    }

    private var regularAccounts: [Account] {
        sortedAccounts.filter { !$0.isDeposit && !$0.isLoan }
    }

    private var depositAccounts: [Account] {
        sortedAccounts.filter { $0.isDeposit }
    }

    private var loanAccounts: [Account] {
        sortedAccounts.filter { $0.isLoan }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    UniversalRow(config: .settings) {
                        Text(String(localized: "filter.allAccounts"))
                            .font(AppTypography.h4)
                            .fontWeight(.medium)
                    } trailing: {
                        if selectedAccountId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .selectableRow(isSelected: selectedAccountId == nil) {
                        HapticManager.selection()
                        selectedAccountId = nil
                        dismiss()
                    }
                }

                if !regularAccounts.isEmpty {
                    accountSection(
                        title: String(localized: "account.type.regular", defaultValue: "Счета"),
                        accounts: regularAccounts
                    )
                }

                if !depositAccounts.isEmpty {
                    accountSection(
                        title: String(localized: "account.type.deposit", defaultValue: "Депозиты"),
                        accounts: depositAccounts
                    )
                }

                if !loanAccounts.isEmpty {
                    accountSection(
                        title: String(localized: "account.type.loan", defaultValue: "Кредиты"),
                        accounts: loanAccounts
                    )
                }
            }
            .navigationTitle(String(localized: "filter.accounts", defaultValue: "Счета"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    // MARK: - Account Section

    private func accountSection(title: String, accounts: [Account]) -> some View {
        Section {
            ForEach(accounts) { account in
                let balance = balanceCoordinator?.balances[account.id] ?? 0

                UniversalRow(
                    config: .settings,
                    leadingIcon: .custom(
                        source: account.iconSource,
                        style: .roundedSquare(size: AppIconSize.xl)
                    )
                ) {
                    HStack(spacing: 0) {
                        Text(account.name)
                            .font(AppTypography.h4)
                            .fontWeight(.medium)

                        Spacer()

                        Text(Formatting.formatCurrencySmart(balance, currency: account.currency))
                            .font(AppTypography.h4)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } trailing: {
                    if selectedAccountId == account.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .selectableRow(isSelected: selectedAccountId == account.id) {
                    HapticManager.selection()
                    selectedAccountId = account.id
                    dismiss()
                }
            }
        } header: {
            SectionHeaderView(title)
        }
    }
}

#Preview {
    AccountFilterView(
        accounts: [
            Account(id: "acc-1", name: "Kaspi Gold", currency: "KZT",
                    iconSource: .sfSymbol("creditcard.fill"), balance: 125_400),
            Account(id: "acc-2", name: "Halyk Bank", currency: "KZT",
                    iconSource: .sfSymbol("building.columns"), balance: 48_900),
        ],
        selectedAccountId: .constant(nil),
        balanceCoordinator: nil
    )
}
