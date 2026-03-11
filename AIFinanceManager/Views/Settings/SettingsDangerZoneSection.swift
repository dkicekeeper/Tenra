//
//  SettingsDangerZoneSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based Danger Zone section for Settings
/// Single Responsibility: Group dangerous actions (reset)
struct SettingsDangerZoneSection: View {
    // MARK: - Props

    let onResetData: () -> Void

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.dangerZone"))) {
            ActionSettingsRow(
                icon: "trash",
                title: String(localized: "settings.resetData"),
                isDestructive: true,
                action: onResetData
            )
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        SettingsDangerZoneSection(
            onResetData: {
            }
        )
    }
}
