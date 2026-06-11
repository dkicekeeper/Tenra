//
//  CloudBackupService.swift
//  Tenra
//
//  Creates, lists, restores, and deletes SQLite backups.
//  Backups live in either the app's local Documents folder or the iCloud Drive
//  ubiquity container, controlled by the `isICloudEnabled` preference. This is
//  plain file storage in iCloud Drive — NOT CloudKit database sync (which was
//  removed 2026-04-22 after HistoryExpired events caused data loss).
//  Uses WAL checkpoint before copying for consistency.
//  Uses CoreDataStack.swapStore() for safe restore.
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
    private let maxBackups = 5

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

    /// Creates a backup of the current SQLite store in the active backups directory
    /// (local Documents, or the iCloud Drive container when iCloud is enabled).
    /// Performs WAL checkpoint before copying for consistency.
    func createBackup(
        transactionCount: Int,
        accountCount: Int,
        categoryCount: Int
    ) async throws -> BackupMetadata {
        guard let backupsDir = backupsDirectoryURL() else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        guard let storeURL = coreDataStack.persistentStoreURL else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        // Flush pending changes to SQLite and checkpoint WAL.
        // Saving the viewContext first ensures all in-memory changes are written.
        // Then we copy .sqlite + .sqlite-wal + .sqlite-shm as a consistent set.
        let viewContext = coreDataStack.viewContext
        try viewContext.performAndWait {
            if viewContext.hasChanges {
                try viewContext.save()
            }
        }

        // Create backup directory with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = backupsDir.appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Copy SQLite file
        let backupStoreURL = backupDir.appendingPathComponent("Tenra.sqlite")
        try FileManager.default.copyItem(at: storeURL, to: backupStoreURL)

        // Also copy WAL and SHM if they exist (belt and suspenders)
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let backupWalURL = backupDir.appendingPathComponent("Tenra.sqlite-wal")
        let backupShmURL = backupDir.appendingPathComponent("Tenra.sqlite-shm")
        if FileManager.default.fileExists(atPath: walURL.path) {
            try? FileManager.default.copyItem(at: walURL, to: backupWalURL)
        }
        if FileManager.default.fileExists(atPath: shmURL.path) {
            try? FileManager.default.copyItem(at: shmURL, to: backupShmURL)
        }

        // Calculate file size
        let attributes = try FileManager.default.attributesOfItem(atPath: backupStoreURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Create and save metadata
        let metadata = BackupMetadata(
            id: UUID().uuidString,
            date: Date(),
            transactionCount: transactionCount,
            accountCount: accountCount,
            categoryCount: categoryCount,
            modelVersion: Self.currentModelVersion,
            fileSize: fileSize,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )

        let metadataURL = backupDir.appendingPathComponent("metadata.json")
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL)

        // Enforce max backups limit
        try enforceMaxBackups()

        CloudBackupService.logger.info("Backup created: \(timestamp), size: \(fileSize) bytes")

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

    /// Ensures a (possibly ubiquitous) file is downloaded before reading it.
    /// No-op for local files. Blocks up to `timeout` seconds — call off the main thread.
    private func ensureDownloaded(_ url: URL, timeout: TimeInterval = 30) {
        let fm = FileManager.default
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        // Local files (status == nil) or already-current files need no wait.
        guard let status, status != .current else { return }

        try? fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if current == .current { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
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

    /// Restores a backup by swapping the persistent store.
    /// Rejects backups with incompatible model versions.
    ///
    /// **Threading**: `swapStore` is dispatched on a detached background task — it
    /// performs file I/O and PSC.add which together can run for hundreds of ms,
    /// and must never block the main thread (watchdog + missed UI frames).
    /// - Parameter metadata: The backup to restore
    func restoreBackup(_ metadata: BackupMetadata) async throws {
        // NOTE: The JSON metadata.modelVersion field is unreliable historical data —
        // all backups were stamped v7 regardless of actual schema. The gate has been
        // moved to a real CoreData store-metadata check inside the Task.detached block
        // below, where the backup SQLite file is inspected directly.

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
                backupStoreURL = dirURL.appendingPathComponent("Tenra.sqlite")
                break
            }
        }

        guard let sourceURL = backupStoreURL else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        // Swap the store off the main thread — file I/O + PSC.addPersistentStore can be slow.
        // For iCloud backups the store files may still be cloud placeholders, so download
        // the full sqlite/wal/shm set (also off the main thread) before swapping.
        let stack = coreDataStack
        try await Task.detached(priority: .userInitiated) { [self] in
            ensureDownloaded(sourceURL)
            ensureDownloaded(URL(fileURLWithPath: sourceURL.path + "-wal"))
            ensureDownloaded(URL(fileURLWithPath: sourceURL.path + "-shm"))
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw CoreDataStack.CloudBackupError.noActiveStore
            }
            // Compatibility gate: read the backup store's own CoreData metadata.
            // - Directly compatible with the current model → restore as-is.
            // - Openable by an older bundled model version → swapStore re-adds the store
            //   with automatic lightweight migration options, so restore is safe.
            // - Neither (e.g. backup made by a NEWER app version) → reject.
            let storeMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: sourceURL, options: nil
            )
            let currentModel = stack.persistentContainer.managedObjectModel
            if !currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: storeMetadata) {
                guard NSManagedObjectModel.mergedModel(from: [.main], forStoreMetadata: storeMetadata) != nil else {
                    throw CoreDataStack.CloudBackupError.incompatibleVersion(metadata.modelVersion)
                }
            }
            try stack.swapStore(from: sourceURL)
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

    // MARK: - Private

    private func enforceMaxBackups() throws {
        var backups = listBackups()
        while backups.count > maxBackups {
            if let oldest = backups.last {
                try deleteBackup(oldest)
                backups.removeLast()
            }
        }
    }
}
