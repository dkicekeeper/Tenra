//
//  SettingsCloudSection.swift
//  Tenra
//
//  iCloud section in Settings — toggle, status, backups navigation, storage.
//  Follows existing SettingsGeneralSection props pattern.
//

import SwiftUI

struct SettingsCloudSection: View {

    let isSyncEnabled: Bool
    let syncState: SyncState
    let storageUsed: Int64
    let onToggleSync: (Bool) -> Void
    let backupsDestination: CloudBackupsView

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.cloud"))) {
            // Sync toggle
            Toggle(isOn: Binding(
                get: { isSyncEnabled },
                set: { onToggleSync($0) }
            )) {
                HStack(spacing: AppSpacing.md) {
                    IconView(
                        source: .sfSymbol("icloud"),
                        style: .circle(size: AppIconSize.md, tint: .monochrome(AppColors.accent))
                    )
                    Text(String(localized: "settings.cloud.sync"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            // Status row (hidden when disabled)
            if isSyncEnabled {
                syncStatusRow
            }

            // Backups navigation
            NavigationSettingsRow(
                icon: "externaldrive.badge.icloud",
                title: String(localized: "settings.cloud.backups")
            ) {
                backupsDestination
            }

            // Storage usage
            UniversalRow(
                config: .settings,
                leadingIcon: .sfSymbol("internaldrive", color: AppColors.accent, size: AppIconSize.md)
            ) {
                Text(String(localized: "settings.cloud.storage"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                Text(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var syncStatusRow: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol(statusIcon, color: statusColor, size: AppIconSize.md)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(statusText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } trailing: {
            EmptyView()
        }
        .animation(AppAnimation.gentleSpring, value: statusText)
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        switch syncState {
        case .idle, .synced: return "checkmark.icloud"
        case .syncing, .initialSync: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        case .noAccount: return "person.crop.circle.badge.exclamationmark"
        case .disabled: return "icloud"
        }
    }

    private var statusColor: Color {
        switch syncState {
        case .idle, .synced: return AppColors.success
        case .syncing, .initialSync: return AppColors.accent
        case .error: return AppColors.destructive
        case .noAccount: return AppColors.warning
        case .disabled: return AppColors.textSecondary
        }
    }

    private var statusText: String {
        switch syncState {
        case .idle, .synced: return String(localized: "settings.cloud.status.synced")
        case .syncing: return String(localized: "settings.cloud.status.syncing")
        case .initialSync: return String(localized: "settings.cloud.status.initialSync")
        case .error(let message): return "\(String(localized: "settings.cloud.status.error")): \(message)"
        case .noAccount: return String(localized: "settings.cloud.status.noAccount")
        case .disabled: return String(localized: "settings.cloud.status.disabled")
        }
    }

    private var statusSubtitle: String? {
        switch syncState {
        case .synced(let lastSync, let sentCount, let receivedCount):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let timeAgo = formatter.localizedString(for: lastSync, relativeTo: Date())
            var subtitle = String(format: String(localized: "settings.cloud.lastSync"), timeAgo)
            if sentCount > 0 || receivedCount > 0 {
                subtitle += "\n" + String(format: String(localized: "settings.cloud.changes"), sentCount, receivedCount)
            }
            return subtitle
        case .initialSync:
            return String(localized: "settings.cloud.status.initialSyncMessage")
        case .idle:
            return nil
        case .syncing, .error, .noAccount, .disabled:
            return nil
        }
    }
}
