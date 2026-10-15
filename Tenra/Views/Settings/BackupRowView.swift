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
            meta: [MetaLine(metadataItems)],
            style: .large
        ) {
            // Affordance hinting the row is tappable to restore.
            Image(systemName: "arrow.counterclockwise")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)
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

    /// "3 accounts · 1,240 transactions · 2.1 MB": the counts in their plural forms, the dots
    /// and the stacking at large text sizes are MetaLine's.
    private var metadataItems: [MetaItem] {
        [
            .text(String(format: NSLocalizedString("finances.accounts.count", comment: "Count with plural forms in Localizable.stringsdict"), metadata.accountCount)),
            .text(String(format: NSLocalizedString("history.count", comment: "Transaction count"), metadata.transactionCount)),
            .text(metadata.formattedFileSize)
        ]
    }
}
