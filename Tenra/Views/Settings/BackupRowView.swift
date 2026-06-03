//
//  BackupRowView.swift
//  Tenra
//
//  Single backup row with metadata and swipe actions.
//

import SwiftUI

struct BackupRowView: View {
    let metadata: BackupMetadata
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(metadata.formattedDate)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Text(metadataLine)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 0)

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
