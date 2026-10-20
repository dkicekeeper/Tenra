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
        Section(
            header: SectionHeader(String(localized: "settings.exportImport"), style: .compact),
            footer: Text(String(localized: "settings.importReminder.footer"))
        ) {
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

            NavigationPickerRow(
                icon: "bell",
                title: String(localized: "settings.importReminder"),
                selection: $reminderDays,
                options: reminderOptions,
                style: .list
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
    List {
        SettingsExportImportSection(
            onExport: {
            },
            onImport: {
            }
        )
    }
}
