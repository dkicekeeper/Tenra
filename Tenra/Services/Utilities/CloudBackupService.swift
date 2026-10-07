//
//  CloudBackupService.swift
//  Tenra
//
//  Creates, lists, restores, and deletes SQLite backups.
//  Backups live in either the app's local Documents folder or the iCloud Drive
//  ubiquity container, controlled by the `isICloudEnabled` preference. This is
//  plain file storage in iCloud Drive — NOT CloudKit database sync (which was
//  removed 2026-04-22 after HistoryExpired events caused data loss).
//
//  A backup is a consistent snapshot of the store taken through SQLite
//  (CoreDataStack.snapshotStore) as one self-contained `Tenra.sqlite`, checked, and only
//  then copied into its folder; `metadata.json` is written last, so a backup that failed
//  half-way is never listed. Restore checks a copy of the backup before the live store is
//  touched and keeps the live files until the restored store has opened
//  (CoreDataStack.swapStore). Manual and automatic backups have separate limits, so the
//  weekly automatic backup never deletes one the user made.
//
//  The container's Documents folder is NOT public (Info.plist
//  `NSUbiquitousContainerIsDocumentScopePublic = false`, since 2026-09-25): a
//  backup is the whole financial history as a readable SQLite file, and it used to
//  show up in the Files app as a "Tenra" folder anyone with the phone could open or
//  share. Backups still sync through iCloud and restore from this screen on every
//  device; data export stays available through CSV. iOS may keep showing the old
//  folder until a build with a higher CFBundleVersion is installed.
//

import Foundation
import CoreData
import os

nonisolated final class CloudBackupService: @unchecked Sendable {

    private nonisolated static let logger = Logger(subsystem: "Tenra", category: "CloudBackupService")

    /// iCloud container identifier — must match `Tenra.entitlements`.
    static let iCloudContainerIdentifier = "iCloud.dakacom.Tenra"

    /// UserDefaults key for the "save backups to iCloud" preference.
    private static let iCloudPreferenceKey = "backups.useICloud"

    private let coreDataStack: CoreDataStack

    /// Most recent manual backups kept. Backups made before the kind was recorded
    /// (2026-10) count as manual, so automatic ones never evict them.
    nonisolated static let maxManualBackups = 5
    /// Most recent automatic backups kept, about a month of weekly ones. Keep in step with
    /// `settings.cloud.autoBackup.footer`.
    nonisolated static let maxAutomaticBackups = 4

    /// The store file inside each backup folder.
    private static let storeFileName = "Tenra.sqlite"

    /// Test seam: when set, backups read/write under this directory instead of
    /// Documents/iCloud. Internal so only the module + @testable tests see it.
    var backupsRootOverride: URL?

    /// Caches the resolved iCloud Documents URL. `nil` = not yet resolved,
    /// `.some(nil)` = resolved-and-unavailable. Guarded by `lock` because this
    /// type is `@unchecked Sendable` and reached from multiple threads.
    private let lock = NSLock()
    private var cachedICloudDocuments: URL??

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }

    // MARK: - iCloud Preference & Availability

    /// Whether the user has opted to store backups in iCloud Drive.
    var isICloudEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.iCloudPreferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.iCloudPreferenceKey) }
    }

    /// Whether an iCloud ubiquity container is reachable (entitlement present + user
    /// signed in). Slow on first call — resolve off the main thread via `prepareICloud()`.
    var isICloudAvailable: Bool { resolveICloudDocumentsURL() != nil }

    /// Resolves (and caches) the iCloud Documents URL. The first
    /// `url(forUbiquityContainerIdentifier:)` call can block for hundreds of ms,
    /// so prefer calling this once off the main thread at launch.
    @discardableResult
    func resolveICloudDocumentsURL() -> URL? {
        lock.lock()
        if let cached = cachedICloudDocuments {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = FileManager.default
            .url(forUbiquityContainerIdentifier: Self.iCloudContainerIdentifier)?
            .appendingPathComponent("Documents", isDirectory: true)

        lock.lock()
        cachedICloudDocuments = .some(resolved)
        lock.unlock()
        return resolved
    }

    /// Primes the iCloud container URL cache off the main thread. Call once at launch.
    func prepareICloud() {
        resolveICloudDocumentsURL()
    }

    // MARK: - Backups Directory

    private func createDirectoryIfNeeded(_ dir: URL) {
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// The Backups directory inside the app's local Documents folder.
    private func localBackupsDirectoryURL() -> URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            CloudBackupService.logger.warning("Documents directory not available")
            return nil
        }
        let backupsDir = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        createDirectoryIfNeeded(backupsDir)
        return backupsDir
    }

    /// The Backups directory inside the iCloud Drive ubiquity container, or `nil`
    /// when iCloud is unavailable.
    private func iCloudBackupsDirectoryURL() -> URL? {
        guard let documentsURL = resolveICloudDocumentsURL() else { return nil }
        let backupsDir = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        createDirectoryIfNeeded(backupsDir)
        return backupsDir
    }

    /// The active Backups directory — iCloud when enabled and available, else local.
    /// Returns `backupsRootOverride` first when set (test seam).
    private func backupsDirectoryURL() -> URL? {
        if let override = backupsRootOverride {
            createDirectoryIfNeeded(override)
            return override
        }
        if isICloudEnabled, let iCloudDir = iCloudBackupsDirectoryURL() {
            return iCloudDir
        }
        return localBackupsDirectoryURL()
    }

    // MARK: - iCloud Migration

    /// Switches the backup destination and moves existing backups to match.
    /// - `enabled == true`: move every local backup into iCloud Drive.
    /// - `enabled == false`: move every iCloud backup back to local storage.
    /// On success the `isICloudEnabled` preference is updated; on failure it is left
    /// untouched so the caller can revert the UI.
    func setICloudEnabled(_ enabled: Bool) throws {
        if enabled {
            guard let destination = iCloudBackupsDirectoryURL() else {
                throw CoreDataStack.CloudBackupError.iCloudUnavailable
            }
            if let source = localBackupsDirectoryURL() {
                try migrateBackups(from: source, to: destination, intoICloud: true)
            }
        } else {
            guard let destination = localBackupsDirectoryURL() else {
                throw CoreDataStack.CloudBackupError.noActiveStore
            }
            // Only migrate out if iCloud is reachable; otherwise there is nothing to move.
            if let source = iCloudBackupsDirectoryURL() {
                try migrateBackups(from: source, to: destination, intoICloud: false)
            }
        }
        isICloudEnabled = enabled
        CloudBackupService.logger.info("iCloud backups \(enabled ? "enabled" : "disabled")")
    }

    /// Moves each backup sub-directory between local and iCloud storage using
    /// `FileManager.setUbiquitous`, which is the supported API for relocating items
    /// into/out of the ubiquity container.
    private func migrateBackups(from source: URL, to destination: URL, intoICloud: Bool) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }

        for itemURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let destURL = destination.appendingPathComponent(itemURL.lastPathComponent, isDirectory: true)
            if fm.fileExists(atPath: destURL.path) { continue } // already present at destination

            // setUbiquitous(true, ...) moves a local item into iCloud;
            // setUbiquitous(false, ...) evicts an iCloud item back to local.
            try fm.setUbiquitous(intoICloud, itemAt: itemURL, destinationURL: destURL)
        }
    }

    // MARK: - Create Backup

    /// Creates a backup of the current store in the active backups directory (local
    /// Documents, or the iCloud Drive container when iCloud is enabled), then applies the
    /// retention of its kind (`backupsToEvict`).
    ///
    /// Throws unless the backup is a complete store that passed its checks. Before 2026-10
    /// it copied `Tenra.sqlite` and then the -wal/-shm with `try?`, so a backup could miss
    /// the newest saves, or pair files from two moments, and still report success.
    func createBackup(
        transactionCount: Int,
        accountCount: Int,
        categoryCount: Int,
        isAutomatic: Bool = false
    ) async throws -> BackupMetadata {
        guard let backupsDir = backupsDirectoryURL() else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        // Write what the view context still holds, so the snapshot has it.
        let viewContext = coreDataStack.viewContext
        try viewContext.performAndWait {
            if viewContext.hasChanges {
                try viewContext.save()
            }
        }

        // 1. Snapshot into a local scratch folder, never straight into iCloud Drive.
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("TenraBackup-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        let snapshotURL = scratch.appendingPathComponent(Self.storeFileName)
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            try coreDataStack.snapshotStore(to: snapshotURL)
        } catch {
            Self.logger.error("Backup snapshot failed: \(error.localizedDescription, privacy: .public)")
            throw CoreDataStack.CloudBackupError.copyFailed(error)
        }

        // 2. Copy it into a new backup folder. metadata.json goes last, so a backup that
        //    failed half-way is never listed, and the folder is removed on a failure.
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        var backupDir = backupsDir.appendingPathComponent(timestamp, isDirectory: true)
        if fm.fileExists(atPath: backupDir.path) {
            backupDir = backupsDir.appendingPathComponent(
                "\(timestamp)-\(UUID().uuidString.prefix(8))", isDirectory: true
            )
        }
        var createdBackupDir = false
        let metadata: BackupMetadata
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: false)
            createdBackupDir = true
            let backupStoreURL = try PersistentStoreFiles.copyStore(at: snapshotURL, into: backupDir)
            metadata = BackupMetadata(
                id: UUID().uuidString,
                date: Date(),
                transactionCount: transactionCount,
                accountCount: accountCount,
                categoryCount: categoryCount,
                modelVersion: Self.currentModelVersion,
                fileSize: PersistentStoreFiles.contentSize(ofStore: backupStoreURL),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                isAutomatic: isAutomatic
            )
            try JSONEncoder().encode(metadata)
                .write(to: backupDir.appendingPathComponent("metadata.json"), options: .atomic)
        } catch {
            if createdBackupDir { try? fm.removeItem(at: backupDir) }
            Self.logger.error("Backup copy failed: \(error.localizedDescription, privacy: .public)")
            throw CoreDataStack.CloudBackupError.copyFailed(error)
        }

        // 3. Retention. A failed eviction leaves one backup too many, not a broken one.
        evictOldBackups(after: metadata)

        Self.logger.info("Backup created: \(backupDir.lastPathComponent, privacy: .public), \(metadata.fileSize) bytes, automatic: \(isAutomatic)")
        return metadata
    }

    // MARK: - List Backups

    /// Returns all available backups sorted by date (newest first)
    func listBackups() -> [BackupMetadata] {
        guard let backupsDir = backupsDirectoryURL() else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var backups: [BackupMetadata] = []
        for dirURL in contents {
            let metadataURL = dirURL.appendingPathComponent("metadata.json")
            // For iCloud backups the metadata may be a not-yet-downloaded placeholder —
            // kick off a download (best effort; throws harmlessly for local files).
            try? fm.startDownloadingUbiquitousItem(at: metadataURL)
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(BackupMetadata.self, from: data) else {
                continue
            }
            backups.append(metadata)
        }

        return backups.sorted { $0.date > $1.date }
    }

    /// Downloads a (possibly) ubiquitous file and waits up to `timeout` seconds for it.
    /// Returns false only for an iCloud item that is still not on this device afterwards;
    /// a local file, or one that doesn't exist at all, returns true. Blocks: call it off
    /// the main thread.
    private func ensureDownloaded(_ url: URL, timeout: TimeInterval = 30) -> Bool {
        // Local files (status == nil) and current ones need no wait.
        guard let status = downloadingStatus(of: url), status != .current else { return true }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if downloadingStatus(of: url) == .current { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The iCloud download status of `url`, read fresh every time (a URL caches its
    /// resource values), or nil for a local file or one that doesn't exist.
    private func downloadingStatus(of url: URL) -> URLUbiquitousItemDownloadingStatus? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
    }

    // MARK: - Restore Backup

    /// Current model version, derived from the compiled model so it can never
    /// drift from the schema again (was hardcoded to v7 while the schema was v12).
    /// Display/diagnostic value only — restore compatibility is decided from the
    /// backup store file's own metadata, not this string.
    nonisolated static let currentModelVersion: String = {
        guard
            let momdURL = Bundle.main.url(forResource: "Tenra", withExtension: "momd"),
            let info = NSDictionary(contentsOf: momdURL.appendingPathComponent("VersionInfo.plist")),
            let current = info["NSManagedObjectModel_CurrentVersionName"] as? String
        else { return "unknown" }
        // "Tenra v12" → "v12"
        return current.components(separatedBy: " ").last ?? current
    }()

    /// Restores a backup by swapping the persistent store (`CoreDataStack.swapStore`), which
    /// checks a copy of the backup first and keeps the live store until the restored one
    /// has opened. Rejects backups the current model can't open, and damaged ones.
    ///
    /// **Threading**: `swapStore` is dispatched on a detached background task — it
    /// performs file I/O, SQLite's page check and PSC.add, which together can run for
    /// hundreds of ms, and must never block the main thread (watchdog + missed UI frames).
    /// - Parameter metadata: The backup to restore
    func restoreBackup(_ metadata: BackupMetadata) async throws {
        // NOTE: The JSON metadata.modelVersion field is unreliable historical data —
        // all backups were stamped v7 regardless of actual schema. The gate is a real
        // CoreData store-metadata check in swapStore, on a copy of the backup's store.

        guard let backupsDir = backupsDirectoryURL() else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        // Find the backup directory matching this metadata
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        var backupStoreURL: URL?
        for dirURL in contents {
            let metadataURL = dirURL.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let m = try? JSONDecoder().decode(BackupMetadata.self, from: data),
               m.id == metadata.id {
                backupStoreURL = dirURL.appendingPathComponent(Self.storeFileName)
                break
            }
        }

        guard let sourceURL = backupStoreURL else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        // Swap the store off the main thread: file I/O, the checks and
        // PSC.addPersistentStore can be slow. For iCloud backups the store files may still be
        // cloud placeholders, so download them first (also off the main thread). A -wal
        // exists only in backups made before 2026-10; restoring without it would silently
        // drop the saves it holds, so a -wal iCloud has must be here too. The -shm is never
        // used.
        let stack = coreDataStack
        let shownVersion = metadata.modelVersion
        try await Task.detached(priority: .userInitiated) { [self] in
            guard ensureDownloaded(sourceURL),
                  ensureDownloaded(PersistentStoreFiles.walURL(ofStore: sourceURL)) else {
                throw CoreDataStack.CloudBackupError.notDownloaded
            }
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw CoreDataStack.CloudBackupError.damagedBackup
            }
            // swapStore applies the compatibility gate on its copy: a backup the current
            // model opens directly or after a lightweight migration from a bundled older
            // version restores; one made by a NEWER app version is rejected.
            do {
                try stack.swapStore(from: sourceURL)
            } catch CoreDataStack.CloudBackupError.incompatibleVersion(_) {
                throw CoreDataStack.CloudBackupError.incompatibleVersion(shownVersion)
            }
        }.value

        CloudBackupService.logger.info("Backup restored: \(metadata.id)")
    }

    // MARK: - Delete Backup

    /// Deletes a specific backup
    func deleteBackup(_ metadata: BackupMetadata) throws {
        guard let backupsDir = backupsDirectoryURL() else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for dirURL in contents {
            let metadataURL = dirURL.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let m = try? JSONDecoder().decode(BackupMetadata.self, from: data),
               m.id == metadata.id {
                try fm.removeItem(at: dirURL)
                CloudBackupService.logger.info("Backup deleted: \(metadata.id)")
                return
            }
        }
    }

    // MARK: - Storage

    /// Estimated iCloud storage used by backups
    func estimateStorageUsed() -> Int64 {
        let backups = listBackups()
        return backups.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Retention

    /// The backups to delete once `created` exists. Each kind has its own limit and only
    /// evicts its own kind: an automatic backup removes older automatic ones, a manual
    /// backup older manual ones. A backup with no recorded kind (made before 2026-10) counts
    /// as manual. `created` itself is never returned.
    ///
    /// One shared limit of 5 used to let the weekly automatic backup push the user's own
    /// backups out within five weeks.
    nonisolated static func backupsToEvict(
        from backups: [BackupMetadata],
        after created: BackupMetadata
    ) -> [BackupMetadata] {
        let isAutomatic = created.isAutomatic == true
        let limit = isAutomatic ? maxAutomaticBackups : maxManualBackups
        let sameKind = backups
            .filter { ($0.isAutomatic == true) == isAutomatic && $0.id != created.id }
            .sorted { $0.date > $1.date }
        // `created` takes one of the slots.
        return Array(sameKind.dropFirst(max(limit - 1, 0)))
    }

    private func evictOldBackups(after created: BackupMetadata) {
        for backup in Self.backupsToEvict(from: listBackups(), after: created) {
            do {
                try deleteBackup(backup)
            } catch {
                Self.logger.error("Old backup \(backup.id, privacy: .public) not deleted: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
