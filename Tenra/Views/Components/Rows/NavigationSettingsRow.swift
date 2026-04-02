//
//  NavigationSettingsRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//  Migrated to UniversalRow architecture - 2026-02-16
//

import SwiftUI

/// Props-based navigation row for Settings
/// Single Responsibility: Display navigation link with icon and title
/// Now built on top of UniversalRow for consistency
struct NavigationSettingsRow<Destination: View>: View {
    // MARK: - Props

    let icon: String
    let title: String
    let iconColor: Color
    let destination: Destination

    // MARK: - Initializer

    init(
        icon: String,
        title: String,
        iconColor: Color = AppColors.accent,
        @ViewBuilder destination: () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.destination = destination()
    }

    // MARK: - Body

    var body: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol(icon, color: iconColor, size: AppIconSize.md)
        ) {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
        } trailing: {
            EmptyView() // NavigationLink автоматически добавит chevron
        }
        .navigationRow {
            destination
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        List {
            NavigationSettingsRow(
                icon: "tag",
                title: String(localized: "settings.categories")
            ) {
                Text("Categories Management")
            }

            NavigationSettingsRow(
                icon: "creditcard",
                title: String(localized: "settings.accounts")
            ) {
                Text("Accounts Management")
            }
        }
    }
}
