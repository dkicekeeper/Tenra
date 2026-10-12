//
//  BackupRowView.swift
//  Tenra
//
//  Single backup row with metadata and swipe actions (DesignKit's ItemRow, .large).
//

import SwiftUI

struct BackupRowView: View {
    let metadata: BackupMetadata
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        // Made by the weekly automatic backup ("Auto" badge): these have their own limit
        // and never replace the ones the user made.
        ItemRow(
            metadata.formattedDate,
            badge: metadata.isAutomatic == true ? String(localized: "settings.cloud.autoBackup.badge") : nil,
            meta: [MetaLine([.text(metadataLine)])],
            style: .large
        ) {
            // Affordance hinting the row is tappable to restore.
            Image(systemName: "arrow.counterclockwise")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onRestore()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: "settings.cloud.restore")))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "settings.cloud.delete"), systemImage: "trash")
            }
        }
    }

    private var metadataLine: String {
        String(format: String(localized: "settings.cloud.backupMetadata"),
               metadata.accountCount, metadata.transactionCount, metadata.formattedFileSize)
    }
}
