//
//  AccountFilterView.swift
//  Tenra
//
//  Account filter sheet for HistoryView
//

import SwiftUI

struct AccountFilterView: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let balanceCoordinator: BalanceCoordinator?

    @Environment(\.dismiss) var dismiss
    @Environment(\.amountsHidden) private var amountsHidden

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
                    CheckmarkRow(String(localized: "filter.allAccounts"), isSelected: selectedAccountId == nil) {
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

                CheckmarkRow(
                    account.name,
                    icon: iconConfig(for: account),
                    value: amountsHidden
                        ? Formatting.hiddenAmount(currency: account.currency)
                        : Formatting.formatCurrencySmart(balance, currency: account.currency),
                    isSelected: selectedAccountId == account.id
                ) {
                    selectedAccountId = account.id
                    dismiss()
                }
            }
        } header: {
            SectionHeader(title)
        }
    }

    // MARK: - Account Icon

    /// Plated like the rest of the app. A logo fills its circle, as in the account rows
    /// (`Icon(source:size:)`). An SF Symbol, which the account rows draw in the accent,
    /// sits on a pale accent circle, the category-row plate: the account rows' `bgCard`
    /// plate is the colour of this sheet's grouped rows in dark mode and would vanish. No
    /// icon: the placeholder on a neutral plate. `xl`, the size these icons already had.
    private func iconConfig(for account: Account) -> IconConfig {
        let style: IconStyle
        switch account.iconSource {
        case .brandService:
            style = .serviceLogo(size: AppIconSize.xl)
        case .sfSymbol:
            style = .circle(
                size: AppIconSize.xl,
                tint: .monochrome(AppColors.accent),
                backgroundColor: AppColors.pale(AppColors.accent)
            )
        case .none:
            style = .circle(
                size: AppIconSize.xl,
                tint: .monochrome(AppColors.textSecondary),
                backgroundColor: AppColors.Status.neutralPale
            )
        }
        return .custom(source: account.iconSource, style: style)
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
