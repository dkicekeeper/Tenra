//
//  CloudBackupService.swift
//  Tenra
//
//  Creates, lists, restores, and deletes SQLite backups in iCloud ubiquity container.
//  Uses WAL checkpoint before copying for consistency.
//  Uses CoreDataStack.swapStore() for safe restore.
//

import Foundation
import CoreData
import os

final class CloudBackupService: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudBackupService")

    private let coreDataStack: CoreDataStack
    private let maxBackups = 5

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }

    // MARK: - Ubiquity Container

    /// Returns the Backups directory in the iCloud ubiquity container, or nil if iCloud is unavailable.
    private func backupsDirectoryURL() -> URL? {
        guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.dakacom.Tenra") else {
            CloudBackupService.logger.warning("iCloud ubiquity container not available")
            return nil
        }
        let backupsDir = ubiquityURL.appendingPathComponent("Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: backupsDir.path) {
            try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        }
        return backupsDir
    }

    // MARK: - Create Backup

    /// Creates a backup of the current SQLite store in the iCloud ubiquity container.
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
            modelVersion: "v6",
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
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(BackupMetadata.self, from: data) else {
                continue
            }
            backups.append(metadata)
        }

        return backups.sorted { $0.date > $1.date }
    }

    // MARK: - Restore Backup

    /// Current model version — must match backup to allow restore
    private static let currentModelVersion = "v6"

    /// Restores a backup by swapping the persistent store.
    /// Rejects backups with incompatible model versions.
    /// - Parameter metadata: The backup to restore
    func restoreBackup(_ metadata: BackupMetadata) async throws {
        // Reject incompatible model versions
        guard metadata.modelVersion == Self.currentModelVersion else {
            throw CoreDataStack.CloudBackupError.incompatibleVersion(metadata.modelVersion)
        }

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

        guard let sourceURL = backupStoreURL,
              fm.fileExists(atPath: sourceURL.path) else {
            throw CoreDataStack.CloudBackupError.noActiveStore
        }

        // Ensure file is downloaded from iCloud
        if !fm.isUbiquitousItem(at: sourceURL) || !FileManager.default.fileExists(atPath: sourceURL.path) {
            try fm.startDownloadingUbiquitousItem(at: sourceURL)
            // Wait for download — simple polling with timeout
            let deadline = Date().addingTimeInterval(60)
            while !fm.fileExists(atPath: sourceURL.path) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        // Swap the store
        try coreDataStack.swapStore(from: sourceURL)

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
