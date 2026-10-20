//
//  SettingsExportImportSection.swift
//  Tenra
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
        Section(header: SectionHeader(String(localized: "settings.exportImport"), style: .compact)) {
            UniversalRow(
                String(localized: "settings.exportData"),
                icon: "square.and.arrow.up",
                config: .settings,
                accessory: .action(onExport)
            )

            UniversalRow(
                String(localized: "settings.importData"),
                icon: "square.and.arrow.down",
                config: .settings,
                accessory: .action(onImport)
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
