//
//  SettingsDataManagementSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based Data Management section for Settings
/// Single Responsibility: Group data management navigation links
struct SettingsDataManagementSection<CategoriesView: View, SubcategoriesView: View, AccountsView: View>: View {
    // MARK: - Props

    let categoriesDestination: CategoriesView
    let subcategoriesDestination: SubcategoriesView
    let accountsDestination: AccountsView

    // MARK: - Initializer

    init(
        @ViewBuilder categoriesDestination: () -> CategoriesView,
        @ViewBuilder subcategoriesDestination: () -> SubcategoriesView,
        @ViewBuilder accountsDestination: () -> AccountsView
    ) {
        self.categoriesDestination = categoriesDestination()
        self.subcategoriesDestination = subcategoriesDestination()
        self.accountsDestination = accountsDestination()
    }

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.dataManagement"))) {
            NavigationSettingsRow(
                icon: "tag",
                title: String(localized: "settings.categories")
            ) {
                categoriesDestination
            }

            NavigationSettingsRow(
                icon: "tag.fill",
                title: String(localized: "settings.subcategories")
            ) {
                subcategoriesDestination
            }

            NavigationSettingsRow(
                icon: "creditcard",
                title: String(localized: "settings.accounts")
            ) {
                accountsDestination
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        List {
            SettingsDataManagementSection {
                Text("Categories Management")
            } subcategoriesDestination: {
                Text("Subcategories Management")
            } accountsDestination: {
                Text("Accounts Management")
            }
        }
    }
}
