//
//  SettingsCloudSection.swift
//  Tenra
//
//  Backups section in Settings — backup list navigation + storage usage.
//  iCloud sync was removed 2026-04-22; despite the name, backups are local files.
//

import SwiftUI

struct SettingsCloudSection: View {

    let storageUsed: Int64
    let backupsDestination: CloudBackupsView

    var body: some View {
        FormSection(header: String(localized: "settings.cloud")) {
            UniversalRow(
                String(localized: "settings.cloud.backups"),
                icon: "externaldrive",
                value: ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file),
                accessory: .navigation { backupsDestination }
            )
        }
    }
}
