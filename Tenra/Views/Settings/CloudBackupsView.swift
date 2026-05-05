//
//  CloudBackupsView.swift
//  Tenra
//
//  Backup list screen with create, restore, and delete.
//

import SwiftUI

struct CloudBackupsView: View {

    let cloudSyncViewModel: CloudSyncViewModel

    /// Counts needed for backup metadata — passed from SettingsView
    let transactionCount: Int
    let accountCount: Int
    let categoryCount: Int

    @State private var showingRestoreAlert = false
    @State private var backupToRestore: BackupMetadata?
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: BackupMetadata?

    var body: some View {
        List {
            if !cloudSyncViewModel.backups.isEmpty {
                Section {
                    ForEach(cloudSyncViewModel.backups) { backup in
                        BackupRowView(
                            metadata: backup,
                            onRestore: {
                                backupToRestore = backup
                                showingRestoreAlert = true
                            },
                            onDelete: {
                                backupToDelete = backup
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    await cloudSyncViewModel.createBackup(
                        transactionCount: transactionCount,
                        accountCount: accountCount,
                        categoryCount: categoryCount
                    )
                }
            } label: {
                HStack {
                    Spacer()
                    if cloudSyncViewModel.isCreatingBackup {
                        ProgressView()
                            .padding(.trailing, AppSpacing.sm)
                    }
                    Text(String(localized: "settings.cloud.createBackup"))
                        .font(AppTypography.body)
                    Spacer()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(cloudSyncViewModel.isCreatingBackup)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(String(localized: "settings.cloud.backups"))
        .navigationBarTitleDisplayMode(.large)
        .disabled(cloudSyncViewModel.isRestoringBackup)
        .overlay {
            if cloudSyncViewModel.isRestoringBackup {
                RestoreProgressOverlay()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(AppAnimation.gentleSpring, value: cloudSyncViewModel.isRestoringBackup)
        .overlay {
            // Toast messages
            VStack {
                if let successMessage = cloudSyncViewModel.successMessage {
                    MessageBanner.success(successMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                if let errorMessage = cloudSyncViewModel.errorMessage {
                    MessageBanner.error(errorMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                Spacer()
            }
        }
        .alert(
            String(localized: "alert.restore.title"),
            isPresented: $showingRestoreAlert
        ) {
            Button(String(localized: "alert.restore.confirm"), role: .destructive) {
                if let backup = backupToRestore {
                    Task { await cloudSyncViewModel.restoreBackup(backup) }
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            if let backup = backupToRestore {
                Text(String(format: String(localized: "alert.restore.message"), backup.formattedDate))
            }
        }
        .alert(
            String(localized: "settings.cloud.delete"),
            isPresented: $showingDeleteAlert
        ) {
            Button(String(localized: "settings.cloud.delete"), role: .destructive) {
                if let backup = backupToDelete {
                    cloudSyncViewModel.deleteBackup(backup)
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        }
        .task {
            cloudSyncViewModel.loadBackups()
        }
    }
}

private struct RestoreProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppColors.accent)

                Text(String(localized: "settings.cloud.restoring"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)

                Text(String(localized: "settings.cloud.restoringSubtitle"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(AppSpacing.xl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .padding(AppSpacing.xl)
        }
        .accessibilityElement(children: .combine)
    }
}
