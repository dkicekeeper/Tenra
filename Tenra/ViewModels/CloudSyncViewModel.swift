//
//  CloudSyncViewModel.swift
//  Tenra
//
//  UI state for backups. CloudKit *database* sync was removed 2026-04-22 —
//  HistoryExpired events were triggering data loss on restart. Backups can now
//  optionally live in the iCloud Drive ubiquity container (plain file storage,
//  not CloudKit) via the `iCloudEnabled` toggle; otherwise they stay on-device
//  in Documents/Backups. The class name is kept to avoid renaming call sites.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class CloudSyncViewModel {

    private nonisolated static let logger = Logger(subsystem: "Tenra", category: "CloudSyncViewModel")

    // MARK: - Observable State

    var backups: [BackupMetadata] = []
    var isCreatingBackup = false
    var isRestoringBackup = false
    var storageUsed: Int64 = 0
    var successMessage: String?
    var errorMessage: String?

    /// Whether backups are stored in the iCloud Drive ubiquity container.
    var iCloudEnabled = false
    /// Whether an iCloud container is reachable (entitlement + signed-in account).
    var iCloudAvailable = false
    /// True while migrating existing backups between local and iCloud storage.
    var isMigratingICloud = false

    /// Weekly automatic backup (default ON). Before 2026-09-24 backups existed only if
    /// the user tapped "Create backup" by hand.
    var automaticBackupsEnabled: Bool {
        didSet { UserDefaults.standard.set(automaticBackupsEnabled, forKey: Self.automaticBackupsKey) }
    }
    private static let automaticBackupsKey = "backups.auto.enabled"
    nonisolated static let automaticBackupInterval: TimeInterval = 7 * 86_400

    // MARK: - Dependencies

    @ObservationIgnored private let backupService: CloudBackupService
    @ObservationIgnored private let coreDataStack: CoreDataStack

    /// Bumped by every write to `backups`, so a background listing that finishes after a
    /// newer create/delete doesn't put the old list back.
    @ObservationIgnored private var listGeneration = 0

    /// Why the last automatic backup failed, until a backup succeeds: the Backups screen keeps
    /// it in a banner (the automatic backup runs at launch, away from that screen).
    private(set) var automaticBackupFailure: String?

    /// Set by AppCoordinator after init — used for full re-initialization after restore
    @ObservationIgnored weak var appCoordinator: AppCoordinator?

    // MARK: - Init

    init(
        backupService: CloudBackupService,
        coreDataStack: CoreDataStack = .shared
    ) {
        self.backupService = backupService
        self.coreDataStack = coreDataStack
        self.iCloudEnabled = backupService.isICloudEnabled
        self.automaticBackupsEnabled =
            (UserDefaults.standard.object(forKey: Self.automaticBackupsKey) as? Bool) ?? true
    }

    // MARK: - Automatic backups

    /// Pure rule, pinned by `AutomaticBackupPolicyTests`: back up when enabled, there is
    /// something to back up, and the newest backup (manual or automatic) is a week old.
    nonisolated static func isAutomaticBackupDue(
        lastBackup: Date?,
        now: Date,
        enabled: Bool,
        transactionCount: Int
    ) -> Bool {
        guard enabled, transactionCount > 0 else { return false }
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= automaticBackupInterval
    }

    /// Creates a backup silently when one is due. Called once the full data load has
    /// finished; cheap when nothing is due (one directory listing off the main actor).
    func runAutomaticBackupIfDue(transactionCount: Int, accountCount: Int, categoryCount: Int) async {
        guard !isCreatingBackup, !isRestoringBackup, !isMigratingICloud else { return }
        let service = backupService
        let lastBackup = await Task.detached(priority: .utility) {
            service.listBackups().first?.date
        }.value
        guard Self.isAutomaticBackupDue(
            lastBackup: lastBackup,
            now: Date(),
            enabled: automaticBackupsEnabled,
            transactionCount: transactionCount
        ) else { return }

        do {
            let metadata = try await service.createBackup(
                transactionCount: transactionCount,
                accountCount: accountCount,
                categoryCount: categoryCount,
                isAutomatic: true
            )
            insertCreatedBackup(metadata)
            automaticBackupFailure = nil
            Self.logger.info("Automatic backup created: \(metadata.id, privacy: .public)")
        } catch {
            // Retried at the next launch (no new backup, so it is still due); the Backups
            // screen shows it meanwhile.
            automaticBackupFailure = error.localizedDescription
            Self.logger.error("Automatic backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts a new backup at the top of the list and drops the ones the service evicted for
    /// it (the same `backupsToEvict` rule, applied to the list in hand).
    private func insertCreatedBackup(_ metadata: BackupMetadata) {
        let evicted = Set(CloudBackupService.backupsToEvict(from: backups, after: metadata).map(\.id))
        backups.removeAll { evicted.contains($0.id) }
        backups.insert(metadata, at: 0)
        listGeneration += 1
        storageUsed = Self.storageUsed(by: backups)
    }

    // MARK: - Backups

    /// Refreshes the list, the storage total and iCloud availability. The listing runs off
    /// the main actor: with iCloud backups on it resolves the ubiquity container, which can
    /// block for hundreds of ms, and AppCoordinator calls this right after the first frame.
    /// One listing serves both the list and the total (estimateStorageUsed lists again).
    func loadBackups() {
        iCloudEnabled = backupService.isICloudEnabled
        listGeneration += 1
        let generation = listGeneration
        let service = backupService
        Task {
            let (listed, available) = await Task.detached(priority: .utility) {
                (service.listBackups(), service.isICloudAvailable)
            }.value
            iCloudAvailable = available
            guard generation == listGeneration else { return }
            backups = listed
            storageUsed = Self.storageUsed(by: listed)
        }
    }

    /// What `CloudBackupService.estimateStorageUsed()` computes, from a list in hand.
    private nonisolated static func storageUsed(by backups: [BackupMetadata]) -> Int64 {
        backups.reduce(0) { $0 + $1.fileSize }
    }

    /// Toggles iCloud backup storage and migrates existing backups to match.
    /// Reverts `iCloudEnabled` to the actual state on failure.
    func setICloudEnabled(_ enabled: Bool) async {
        guard enabled != backupService.isICloudEnabled else { return }
        isMigratingICloud = true
        iCloudEnabled = enabled // optimistic — reflect intent immediately
        let service = backupService
        do {
            try await Task.detached(priority: .userInitiated) {
                try service.setICloudEnabled(enabled)
            }.value
            loadBackups()
            await showSuccess(String(localized: enabled
                ? "settings.cloud.iCloud.movedToICloud"
                : "settings.cloud.iCloud.movedToLocal"))
        } catch {
            iCloudEnabled = backupService.isICloudEnabled // revert toggle
            await showError(error.localizedDescription)
        }
        isMigratingICloud = false
    }

    func createBackup(transactionCount: Int, accountCount: Int, categoryCount: Int) async {
        isCreatingBackup = true
        do {
            let metadata = try await backupService.createBackup(
                transactionCount: transactionCount,
                accountCount: accountCount,
                categoryCount: categoryCount
            )
            insertCreatedBackup(metadata)
            automaticBackupFailure = nil
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
            listGeneration += 1
            storageUsed = Self.storageUsed(by: backups)
        } catch {
            Task { await showError(error.localizedDescription) }
        }
    }

    // MARK: - New installs, a new phone, the one-time ask

    /// Set once the person has a decision on iCloud backups: a new install got them on, or an
    /// older one answered the one-time ask on Home.
    nonisolated static let iCloudDecidedKey = "backups.iCloud.decided"

    /// An install from before iCloud backups were on by default (1.7), with iCloud reachable
    /// and backups still on the phone: Home asks once (`ICloudBackupAskCard`).
    var shouldAskForICloud: Bool {
        !UserDefaults.standard.bool(forKey: Self.iCloudDecidedKey) && !iCloudEnabled && iCloudAvailable
    }

    /// The answer to the one-time ask: on moves the backups to iCloud Drive, either way it
    /// never shows again.
    func answerICloudAsk(enable: Bool) async {
        UserDefaults.standard.set(true, forKey: Self.iCloudDecidedKey)
        if enable { await setICloudEnabled(true) }
    }

    /// A new install keeps its backups in iCloud Drive from the start (owner's decision
    /// 2026-10-22): a phone set up from scratch or a reinstall then finds the data. Quiet, no
    /// banner; nothing without an iCloud account, and a person can still turn it off.
    func adoptICloudForNewInstall() async {
        UserDefaults.standard.set(true, forKey: Self.iCloudDecidedKey)
        let service = backupService
        let enabled = await Task.detached(priority: .utility) { () -> Bool in
            if service.isICloudEnabled { return true }
            guard service.isICloudAvailable else { return false }
            return (try? service.setICloudEnabled(true)) != nil
        }.value
        iCloudEnabled = enabled
    }

    /// The backups iCloud Drive holds, for the welcome screen. iCloud may still be fetching
    /// the folder on a new phone, so it is listed a few times a second apart (polls, not a
    /// deadline).
    func iCloudBackupsForRestore(attempts: Int = 4) async -> [BackupMetadata] {
        let service = backupService
        for attempt in 0..<attempts {
            let found = await Task.detached(priority: .userInitiated) { service.listICloudBackups() }.value
            if !found.isEmpty { return found }
            if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(1)) }
        }
        return []
    }

    /// Restores an iCloud backup before onboarding has created anything. iCloud backups go on
    /// first (that is where the backup lives, and where the next ones should go), the store is
    /// swapped and reloaded, and the base currency follows the restored accounts: settings live
    /// in UserDefaults, outside the backup. True when the data is back.
    func restoreFromOnboarding(_ metadata: BackupMetadata) async -> Bool {
        isRestoringBackup = true
        defer { isRestoringBackup = false }
        let service = backupService
        do {
            try await Task.detached(priority: .userInitiated) {
                if !service.isICloudEnabled { try service.setICloudEnabled(true) }
            }.value
            iCloudEnabled = true
            UserDefaults.standard.set(true, forKey: Self.iCloudDecidedKey)
            try await service.restoreBackup(metadata)
        } catch {
            await showError(error.localizedDescription)
            return false
        }
        guard let coordinator = appCoordinator else { return true }
        try? await coordinator.transactionStore.loadData()
        coordinator.syncTransactionStoreToViewModels(batchMode: true)
        await coordinator.balanceCoordinator.registerAccounts(coordinator.transactionStore.accounts)
        if let currency = Self.dominantCurrency(of: coordinator.transactionStore.accounts) {
            await coordinator.settingsViewModel.updateBaseCurrency(currency)
        }
        return true
    }

    /// The currency most accounts are kept in (ties: the first account's), loans aside.
    nonisolated static func dominantCurrency(of accounts: [Account]) -> String? {
        let candidates = accounts.filter { !$0.isLoan }
        guard let first = candidates.first else { return accounts.first?.currency }
        var counts: [String: Int] = [:]
        for account in candidates { counts[account.currency, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        return counts[first.currency] == best
            ? first.currency
            : counts.filter { $0.value == best }.keys.sorted().first
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
