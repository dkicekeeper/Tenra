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
        // DesignKit 8.0.0: glass sections on the page (a List of system toggles before).
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                FormSection(footer: String(localized: cloudSyncViewModel.iCloudAvailable
                    ? "settings.cloud.iCloud.footer"
                    : "settings.cloud.iCloud.unavailable")) {
                    UniversalRow(
                        String(localized: "settings.cloud.iCloud.toggle"),
                        icon: "icloud",
                        hint: cloudSyncViewModel.isMigratingICloud ? String(localized: "settings.cloud.iCloud.moving", defaultValue: "Moving…") : nil,
                        accessory: .toggle(Binding(
                            get: { cloudSyncViewModel.iCloudEnabled },
                            set: { newValue in
                                Task { await cloudSyncViewModel.setICloudEnabled(newValue) }
                            }
                        ))
                    )
                    .disabled(cloudSyncViewModel.isMigratingICloud || !cloudSyncViewModel.iCloudAvailable)
                }

                // A failed automatic backup stays in sight until a backup succeeds (DesignKit's
                // StatusBanner).
                if let failure = cloudSyncViewModel.automaticBackupFailure {
                    StatusBanner(
                        String(format: String(localized: "settings.cloud.autoBackup.failed"), failure),
                        status: .negative
                    )
                }

                FormSection(footer: String(localized: "settings.cloud.autoBackup.footer")) {
                    UniversalRow(
                        String(localized: "settings.cloud.autoBackup.toggle"),
                        icon: "clock.arrow.circlepath",
                        accessory: .toggle(Binding(
                            get: { cloudSyncViewModel.automaticBackupsEnabled },
                            set: { cloudSyncViewModel.automaticBackupsEnabled = $0 }
                        ))
                    )
                }

                if !cloudSyncViewModel.backups.isEmpty {
                    FormSection(footer: String(localized: "settings.cloud.tapToRestoreHint")) {
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
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
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
            .dsButton()
            .disabled(cloudSyncViewModel.isCreatingBackup)
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(String(localized: "settings.cloud.backups"))
        .navigationBarTitleDisplayMode(.large)
        .disabled(cloudSyncViewModel.isRestoringBackup)
        .progressOverlay(
            isPresented: cloudSyncViewModel.isRestoringBackup,
            title: String(localized: "settings.cloud.restoring"),
            message: String(localized: "settings.cloud.restoringSubtitle")
        )
        .animation(AppAnimation.gentleSpring, value: cloudSyncViewModel.isRestoringBackup)
        .overlay {
            // Toast messages
            VStack {
                if let successMessage = cloudSyncViewModel.successMessage {
                    MessageBanner.success(successMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.popIn)
                        .zIndex(1)
                }
                if let errorMessage = cloudSyncViewModel.errorMessage {
                    MessageBanner.error(errorMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.popIn)
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

