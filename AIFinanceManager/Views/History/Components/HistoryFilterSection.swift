//
//  HistoryFilterSection.swift
//  AIFinanceManager
//
//  Filter section component for HistoryView
//  Phase 14: Migrated to UniversalFilterButton
//

import SwiftUI

struct HistoryFilterSection: View {
    let timeFilterDisplayName: String
    let accounts: [Account]
    let selectedCategories: Set<String>?
    let customCategories: [CustomCategory]
    let incomeCategories: [String]
    @Binding var selectedAccountFilter: String?
    @Binding var showingCategoryFilter: Bool
    let onTimeFilterTap: () -> Void
    let balanceCoordinator: BalanceCoordinator?

    // MARK: - Computed Properties

    private var selectedAccount: Account? {
        accounts.first(where: { $0.id == selectedAccountFilter })
    }

    private var accountFilterTitle: String {
        selectedAccountFilter == nil ? String(localized: "filter.allAccounts") : (selectedAccount?.name ?? String(localized: "filter.allAccounts"))
    }

    private var categoryFilterTitle: String {
        CategoryFilterHelper.displayText(for: selectedCategories)
    }

    private var sortedAccounts: [Account] {
        accounts.sortedByOrder()
    }

    var body: some View {
        UniversalCarousel(config: .filter) {
            // Time filter button
            UniversalFilterButton(
                title: timeFilterDisplayName,
                isSelected: false,
                onTap: onTimeFilterTap
            ) {
                Image(systemName: "calendar")
            }

            // Account filter menu
            UniversalFilterButton(
                title: accountFilterTitle,
                isSelected: selectedAccountFilter != nil
            ) {
                if let account = selectedAccount {
                    IconView(source: account.iconSource, size: AppIconSize.sm)
                }
            } menuContent: {
                // "All accounts" option
                Button(action: { selectedAccountFilter = nil }) {
                    HStack {
                        Text(String(localized: "filter.allAccounts"))
                        Spacer()
                        if selectedAccountFilter == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                // Account list
                ForEach(sortedAccounts) { account in
                    Button(action: { selectedAccountFilter = account.id }) {
                        HStack(spacing: AppSpacing.sm) {
                            IconView(source: account.iconSource, size: AppIconSize.md)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(AppTypography.bodySmall)
                                let balance = balanceCoordinator?.balances[account.id] ?? 0
                                Text(Formatting.formatCurrencySmart(balance, currency: account.currency))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedAccountFilter == account.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Category filter button
            UniversalFilterButton(
                title: categoryFilterTitle,
                isSelected: selectedCategories != nil,
                onTap: { showingCategoryFilter = true }
            ) {
                CategoryFilterHelper.iconView(
                    for: selectedCategories,
                    customCategories: customCategories,
                    incomeCategories: incomeCategories
                )
            }
        }
    }
}

private let previewAccounts = [
    Account(id: "acc-1", name: "Kaspi Gold", currency: "KZT",
            iconSource: .sfSymbol("creditcard.fill"), balance: 125_400),
    Account(id: "acc-2", name: "Halyk Bank", currency: "KZT",
            iconSource: .sfSymbol("building.columns"), balance: 48_900),
    Account(id: "acc-3", name: "USD Cash", currency: "USD",
            iconSource: .sfSymbol("dollarsign.circle"), balance: 520),
]

#Preview("Default — No Filters") {
    let coordinator = AppCoordinator()
    HistoryFilterSection(
        timeFilterDisplayName: "Этот месяц",
        accounts: previewAccounts,
        selectedCategories: nil,
        customCategories: [],
        incomeCategories: ["Salary"],
        selectedAccountFilter: .constant(nil),
        showingCategoryFilter: .constant(false),
        onTimeFilterTap: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
    )
    .padding()
}

#Preview("Account Selected") {
    let coordinator = AppCoordinator()
    HistoryFilterSection(
        timeFilterDisplayName: "Этот месяц",
        accounts: previewAccounts,
        selectedCategories: nil,
        customCategories: [],
        incomeCategories: ["Salary"],
        selectedAccountFilter: .constant("acc-1"),
        showingCategoryFilter: .constant(false),
        onTimeFilterTap: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
    )
    .padding()
}

#Preview("Category Selected") {
    HistoryFilterSection(
        timeFilterDisplayName: "Всё время",
        accounts: previewAccounts,
        selectedCategories: ["Еда и напитки"],
        customCategories: [],
        incomeCategories: [],
        selectedAccountFilter: .constant(nil),
        showingCategoryFilter: .constant(false),
        onTimeFilterTap: {},
        balanceCoordinator: nil
    )
    .padding()
}

#Preview("All Filters Active") {
    let coordinator = AppCoordinator()
    HistoryFilterSection(
        timeFilterDisplayName: "Этот год",
        accounts: previewAccounts,
        selectedCategories: ["Транспорт"],
        customCategories: [],
        incomeCategories: [],
        selectedAccountFilter: .constant("acc-2"),
        showingCategoryFilter: .constant(false),
        onTimeFilterTap: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
    )
    .padding()
}
