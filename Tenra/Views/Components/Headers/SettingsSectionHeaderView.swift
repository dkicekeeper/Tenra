//
//  SettingsSectionHeaderView.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based section header for Settings
/// Single Responsibility: Display section header with consistent styling
struct SettingsSectionHeaderView: View {
    // MARK: - Props

    let title: String

    // MARK: - Body

    var body: some View {
        Text(title)
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
    }
}

// MARK: - Preview

#Preview {
    List {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.general"))) {
            Text("Example row")
        }

        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.dataManagement"))) {
            Text("Another row")
        }
    }
}
