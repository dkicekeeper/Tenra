//
//  OnboardingRestoreSheet.swift
//  Tenra
//
//  "Restore from a backup" on the welcome screen: the backups iCloud Drive holds for Tenra (a
//  new phone, a reinstall), newest first. A tap restores at once: nothing was created yet, so
//  nothing is replaced. Onboarding then ends on the restored data
//  (OnboardingViewModel.restore, CloudSyncViewModel.restoreFromOnboarding).
//

import SwiftUI

struct OnboardingRestoreSheet: View {
    @Bindable var vm: OnboardingViewModel
    let cloudSync: CloudSyncViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    FormSection(footer: String(localized: "onboarding.restore.hint")) {
                        ForEach(vm.cloudBackups) { backup in
                            BackupRowView(metadata: backup, onRestore: {
                                Task { await vm.restore(backup) }
                            })
                        }
                    }
                    .disabled(cloudSync.isRestoringBackup)

                    if cloudSync.isRestoringBackup {
                        InlineStatusText(message: String(localized: "settings.cloud.restoring"), type: .info)
                    } else if let error = cloudSync.errorMessage {
                        InlineStatusText(message: error, type: .error)
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle(String(localized: "onboarding.restore"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "button.cancel")) { dismiss() }
                        .disabled(cloudSync.isRestoringBackup)
                }
            }
        }
        .interactiveDismissDisabled(cloudSync.isRestoringBackup)
    }
}
