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
        Section(header: SectionHeader(String(localized: "settings.cloud"), style: .compact)) {
            UniversalRow(
                config: .settings,
                leadingIcon: .sfSymbol("externaldrive", color: AppColors.accent, size: AppIconSize.md)
            ) {
                Text(String(localized: "settings.cloud.backups"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                Text(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .navigationRow {
                backupsDestination
            }
        }
    }
}
