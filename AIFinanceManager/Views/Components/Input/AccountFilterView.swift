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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.sm) {
                    // "All Accounts" option
                    UniversalRow(config: .sheetList) {
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

                    Divider()
                        .padding(.leading, AppSpacing.lg)

                    // Account list
                    ForEach(Array(sortedAccounts.enumerated()), id: \.element.id) { index, account in
                        let balance = balanceCoordinator?.balances[account.id] ?? 0

                        UniversalRow(
                            config: .sheetList,
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

                        if index < sortedAccounts.count - 1 {
                            Divider()
                                .padding(.leading, AppSpacing.lg)
                        }
                    }
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
