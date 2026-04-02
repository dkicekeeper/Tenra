//
//  CloudSyncViewModel.swift
//  Tenra
//
//  UI state for iCloud sync settings.
//  Coordinates CloudSyncService, CloudSyncSettingsService, and CloudBackupService.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class CloudSyncViewModel {

    private nonisolated static let logger = Logger(subsystem: "Tenra", category: "CloudSyncViewModel")

    // MARK: - Observable State

    var syncState: SyncState = .disabled
    var backups: [BackupMetadata] = []
    var isCreatingBackup = false
    var isRestoringBackup = false
    var storageUsed: Int64 = 0
    var successMessage: String?
    var errorMessage: String?

    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
        }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let syncService: CloudSyncService
    @ObservationIgnored private let settingsService: CloudSyncSettingsService
    @ObservationIgnored private let backupService: CloudBackupService
    @ObservationIgnored private let coreDataStack: CoreDataStack

    /// Set by AppCoordinator after init — used for full re-initialization after restore
    @ObservationIgnored weak var appCoordinator: AppCoordinator?

    // MARK: - Init

    init(
        syncService: CloudSyncService,
        settingsService: CloudSyncSettingsService,
        backupService: CloudBackupService,
        coreDataStack: CoreDataStack = .shared
    ) {
        self.syncService = syncService
        self.settingsService = settingsService
        self.backupService = backupService
        self.coreDataStack = coreDataStack

        // Setup callbacks
        syncService.onSyncStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.syncState = state
            }
        }

        settingsService.onRemoteSettingsChanged = { [weak self] changes in
            Task { @MainActor in
                self?.handleRemoteSettingsChanged(changes)
            }
        }
    }

    // MARK: - Sync Toggle

    func toggleSync() async {
        if isSyncEnabled {
            // Turning OFF — confirm first (handled by view alert)
            disableSync()
        } else {
            await enableSync()
        }
    }

    func enableSync() async {
        let hasAccount = await syncService.checkiCloudAccountStatus()
        guard hasAccount else {
            syncState = .noAccount
            return
        }

        isSyncEnabled = true
        syncState = .initialSync
        coreDataStack.reloadContainer()

        // Check if CloudKit container actually loaded (fallback resets the flag)
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else {
            // CloudKit container failed — fallback to local already happened
            syncState = .error("CoreData model is not yet CloudKit-compatible")
            CloudSyncViewModel.logger.error("CloudKit container failed to load — sync disabled automatically")
            return
        }

        // Reload in-memory data from the new container
        if let coordinator = appCoordinator {
            try? await coordinator.transactionStore.loadData()
            coordinator.syncTransactionStoreToViewModels(batchMode: true)
            await coordinator.balanceCoordinator.registerAccounts(coordinator.transactionStore.accounts)
        }

        syncService.startMonitoring()
        settingsService.startListening()
        settingsService.pushAllToCloud()

        CloudSyncViewModel.logger.info("iCloud sync enabled")
    }

    func disableSync() {
        isSyncEnabled = false
        syncState = .disabled
        syncService.stopMonitoring()
        settingsService.stopListening()
        coreDataStack.reloadContainer()

        // Reload in-memory data from the new (non-CloudKit) container
        if let coordinator = appCoordinator {
            Task {
                try? await coordinator.transactionStore.loadData()
                coordinator.syncTransactionStoreToViewModels(batchMode: true)
                await coordinator.balanceCoordinator.registerAccounts(coordinator.transactionStore.accounts)
            }
        }

        CloudSyncViewModel.logger.info("iCloud sync disabled")
    }

    // MARK: - Backups

    func loadBackups() {
        backups = backupService.listBackups()
        storageUsed = backupService.estimateStorageUsed()
    }

    func createBackup(transactionCount: Int, accountCount: Int, categoryCount: Int) async {
        isCreatingBackup = true
        do {
            let metadata = try await backupService.createBackup(
                transactionCount: transactionCount,
                accountCount: accountCount,
                categoryCount: categoryCount
            )
            backups.insert(metadata, at: 0)
            storageUsed = backupService.estimateStorageUsed()
            await showSuccess(String(localized: "settings.cloud.backupCreated"))
        } catch {
            await showError(error.localizedDescription)
        }
        isCreatingBackup = false
    }

    func restoreBackup(_ metadata: BackupMetadata) async {
        isRestoringBackup = true
        do {
            try await backupService.restoreBackup(metadata)
            // swapStore posts storeDidResetNotification (FRC rebuilds) but in-memory
            // stores (TransactionStore, BalanceCoordinator, etc.) need a full reload.
            if let coordinator = appCoordinator {
                try? await coordinator.transactionStore.loadData()
                coordinator.syncTransactionStoreToViewModels(batchMode: true)
                await coordinator.balanceCoordinator.registerAccounts(coordinator.transactionStore.accounts)
            }
            await showSuccess(String(localized: "settings.cloud.restoreSuccess"))
        } catch {
            await showError(error.localizedDescription)
        }
        isRestoringBackup = false
    }

    func deleteBackup(_ metadata: BackupMetadata) {
        do {
            try backupService.deleteBackup(metadata)
            backups.removeAll { $0.id == metadata.id }
            storageUsed = backupService.estimateStorageUsed()
        } catch {
            Task { await showError(error.localizedDescription) }
        }
    }

    // MARK: - Settings Sync

    /// Push a setting change to iCloud (called from SettingsViewModel on user action)
    func pushSettingToCloud(key: String, value: Any) {
        guard isSyncEnabled else { return }
        settingsService.pushToCloud(key: key, value: value)
    }

    private func handleRemoteSettingsChanged(_ changes: [String: Any]) {
        CloudSyncViewModel.logger.info("Applied \(changes.count) remote settings")
        // SettingsService reads from UserDefaults, which was already updated
        // by CloudSyncSettingsService. UI will update via @Observable.
    }

    // MARK: - Initialize on App Start

    func initializeIfNeeded() async {
        guard isSyncEnabled else {
            syncState = .disabled
            return
        }

        let hasAccount = await syncService.checkiCloudAccountStatus()
        guard hasAccount else {
            syncState = .noAccount
            return
        }

        syncState = .idle
        syncService.startMonitoring()
        settingsService.startListening()
        loadBackups()
    }

    // MARK: - Messages

    private func showSuccess(_ message: String) async {
        successMessage = message
        try? await Task.sleep(for: .seconds(3))
        successMessage = nil
    }

    private func showError(_ message: String) async {
        errorMessage = message
        try? await Task.sleep(for: .seconds(5))
        errorMessage = nil
    }
}
