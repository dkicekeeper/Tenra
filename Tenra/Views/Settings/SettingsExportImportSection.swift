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

    /// Days between reminders to import a bank statement, 0 = off (StatementImportReminder).
    @AppStorage(StatementImportReminder.intervalKey)
    private var reminderDays = StatementImportReminder.defaultIntervalDays

    // MARK: - Body

    var body: some View {
        FormSection(
            header: String(localized: "settings.exportImport"),
            footer: String(localized: "settings.importReminder.footer")
        ) {
            UniversalRow(
                String(localized: "settings.exportData"),
                icon: "square.and.arrow.up",
                accessory: .action(onExport)
            )

            UniversalRow(
                String(localized: "settings.importData"),
                icon: "square.and.arrow.down",
                accessory: .action(onImport)
            )

            UniversalRow(
                String(localized: "settings.importReminder"),
                icon: "bell",
                accessory: .picker($reminderDays, options: reminderOptions)
            )
        }
        .onChange(of: reminderDays) { _, _ in
            Task { await StatementImportReminder.reschedule() }
        }
    }

    private var reminderOptions: [(label: String, value: Int)] {
        StatementImportReminder.intervalChoices.map { days -> (label: String, value: Int) in
            switch days {
            case 0: return (String(localized: "settings.importReminder.off"), days)
            case 7: return (String(localized: "settings.importReminder.week"), days)
            case 14: return (String(localized: "settings.importReminder.twoWeeks"), days)
            default: return (String(localized: "settings.importReminder.month"), days)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        SettingsExportImportSection(
            onExport: {
            },
            onImport: {
            }
        )
    }
}
