//
//  BackupRowView.swift
//  Tenra
//
//  Single backup row with metadata (DesignKit's ItemRow, .large): a tap restores, a long press
//  shows Restore and Delete (DesignKit 8.0.0: no swipe actions).
//

import SwiftUI

struct BackupRowView: View {
    let metadata: BackupMetadata
    let onRestore: () -> Void
    /// None on the welcome screen's restore list: there a backup is only restored.
    var onDelete: (() -> Void)? = nil

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
            Icon("arrow.counterclockwise", size: AppIconSize.sm)
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
        .contextMenu {
            Button {
                onRestore()
            } label: {
                Label(String(localized: "settings.cloud.restore"), systemImage: "arrow.counterclockwise")
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(String(localized: "settings.cloud.delete"), systemImage: "trash")
                }
            }
        }
        .accessibilityAction(named: Text(String(localized: "settings.cloud.delete"))) {
            onDelete?()
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
