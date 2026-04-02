//
//  SettingsExportImportSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based Export/Import section for Settings
/// Single Responsibility: Group export and import actions
struct SettingsExportImportSection: View {
    // MARK: - Props

    let onExport: () -> Void
    let onImport: () -> Void

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.exportImport"))) {
            ActionSettingsRow(
                icon: "square.and.arrow.up",
                title: String(localized: "settings.exportData"),
                action: onExport
            )

            ActionSettingsRow(
                icon: "square.and.arrow.down",
                title: String(localized: "settings.importData"),
                action: onImport
            )
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        SettingsExportImportSection(
            onExport: {
            },
            onImport: {
            }
        )
    }
}
