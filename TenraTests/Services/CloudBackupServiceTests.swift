//
//  CloudBackupServiceTests.swift
//  TenraTests
//
//  Tests for CloudBackupService backup/restore lifecycle.
//  Covers: derived model-version constant, createBackup stamping, round-trip
//  restore, legacy "v7"-stamped backup compatibility, and garbage-file rejection.
//

import Testing
import CoreData
import Foundation
@testable import Tenra

// MARK: - Suite

/// Run serially — each test creates/restores SQLite stores in temp directories.
/// @MainActor because the suite constructs CoreDataStack, which is implicitly
/// MainActor-isolated under the project's SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
@MainActor
@Suite("CloudBackupServiceTests", .serialized)
struct CloudBackupServiceTests {

    // MARK: - Fixture helpers

    /// Builds a real on-disk NSPersistentContainer in a unique temp directory.
    /// Returns (container, storeURL). Caller owns cleanup.
    private func makeOnDiskContainer() throws -> (NSPersistentContainer, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TenraTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("Tenra.sqlite")

        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        // Enable lightweight migration — same options as the production store.
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let error = loadError { throw error }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return (container, storeURL)
    }

    /// Builds a CoreDataStack (test seam) + CloudBackupService wired to a temp backups dir.
    private func makeService() throws -> (CloudBackupService, CoreDataStack, URL) {
        let (container, _) = try makeOnDiskContainer()
        let stack = CoreDataStack(container: container)
        let backupsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TenraBackups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        let service = CloudBackupService(coreDataStack: stack)
        service.backupsRootOverride = backupsRoot
        return (service, stack, backupsRoot)
    }

    /// Seeds a few TransactionEntity rows into the container's viewContext and saves.
    private func seedTransactions(count: Int, in container: NSPersistentContainer) {
        let ctx = container.viewContext
        ctx.performAndWait {
            for i in 0..<count {
                let entity = TransactionEntity(context: ctx)
                entity.id = UUID().uuidString
                entity.date = Date(timeIntervalSince1970: Double(1_700_000_000 + i * 86400))
                entity.descriptionText = "Test \(i)"
                entity.amount = Double(i + 1) * 10.0
                entity.currency = "KZT"
                entity.type = "expense"
                entity.category = "Food"
                entity.createdAt = Date()
            }
            try? ctx.save()
        }
    }

    /// Returns the count of TransactionEntity rows in the container's viewContext.
    private func transactionCount(in container: NSPersistentContainer) -> Int {
        var count = 0
        container.viewContext.performAndWait {
            let req = TransactionEntity.fetchRequest()
            count = (try? container.viewContext.count(for: req)) ?? -1
        }
        return count
    }

    // MARK: - Test 1: currentModelVersion is derived, not stale

    @Test("currentModelVersion is derived from the compiled model and >= 12")
    func currentModelVersionIsDerived() {
        let version = CloudBackupService.currentModelVersion
        #expect(version != "unknown", "momd lookup failed — check Bundle.main resource")

        // Parse the integer from "v12" etc.
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parsed = Int(trimmed)
        #expect(parsed != nil, "Version '\(version)' is not in expected 'v<N>' format")
        if let n = parsed {
            #expect(n >= 12, "Expected schema >= v12, got v\(n) — update this floor if schema bumped")
        }
    }

    // MARK: - Test 2: createBackup stamps the derived version

    @Test("createBackup stamps currentModelVersion in metadata")
    func createBackupStampsDerivedVersion() async throws {
        let (service, stack, backupsRoot) = try makeService()
        let container = stack.persistentContainer
        seedTransactions(count: 3, in: container)

        let metadata = try await service.createBackup(
            transactionCount: 3, accountCount: 0, categoryCount: 0
        )

        #expect(metadata.modelVersion == CloudBackupService.currentModelVersion,
                "createBackup should stamp the derived version, not 'v7'")

        // Verify the backup directory contains both Tenra.sqlite and metadata.json
        let backupDirs = try FileManager.default.contentsOfDirectory(
            at: backupsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        #expect(backupDirs.count == 1, "Expected exactly one backup directory")
        if let dir = backupDirs.first {
            let sqliteExists = FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Tenra.sqlite").path
            )
            let metadataExists = FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("metadata.json").path
            )
            #expect(sqliteExists, "Tenra.sqlite not found in backup directory")
            #expect(metadataExists, "metadata.json not found in backup directory")
        }
    }

    // MARK: - Test 3: Restore round-trip

    @Test("Restore round-trip: post-restore entity count matches backed-up count")
    func restoreRoundTrip() async throws {
        let (service, stack, _) = try makeService()
        let container = stack.persistentContainer

        // Seed 3 transactions and create a backup.
        seedTransactions(count: 3, in: container)
        let metadata = try await service.createBackup(
            transactionCount: 3, accountCount: 0, categoryCount: 0
        )

        // Mutate the live store: add one more transaction.
        seedTransactions(count: 1, in: container)
        let countBeforeRestore = transactionCount(in: container)
        #expect(countBeforeRestore == 4, "Expected 4 transactions after seeding extra")

        // Restore the backup.
        try await service.restoreBackup(metadata)

        // After restore the store should be back to 3.
        let countAfterRestore = transactionCount(in: container)
        #expect(countAfterRestore == 3,
                "After restore the store should have 3 transactions, got \(countAfterRestore)")
    }

    // MARK: - Test 4: Legacy "v7"-stamped backup still restores

    @Test("Legacy 'v7'-stamped backup (existing user backups) restores successfully")
    func legacyV7StampedBackupRestores() async throws {
        let (service, stack, backupsRoot) = try makeService()
        let container = stack.persistentContainer

        seedTransactions(count: 2, in: container)
        let metadata = try await service.createBackup(
            transactionCount: 2, accountCount: 0, categoryCount: 0
        )

        // Rewrite metadata.json on disk with modelVersion forced to "v7",
        // simulating the existing user backup format.
        let backupDirs = try FileManager.default.contentsOfDirectory(
            at: backupsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        let backupDir = try #require(backupDirs.first, "Expected one backup dir")
        let metadataURL = backupDir.appendingPathComponent("metadata.json")
        let legacyMetadata = BackupMetadata(
            id: metadata.id,
            date: metadata.date,
            transactionCount: metadata.transactionCount,
            accountCount: metadata.accountCount,
            categoryCount: metadata.categoryCount,
            modelVersion: "v7",
            fileSize: metadata.fileSize,
            appVersion: metadata.appVersion
        )
        let legacyData = try JSONEncoder().encode(legacyMetadata)
        try legacyData.write(to: metadataURL)

        // Restore using the "v7"-stamped metadata — must succeed.
        try await service.restoreBackup(legacyMetadata)

        let countAfterRestore = transactionCount(in: container)
        #expect(countAfterRestore == 2,
                "Legacy v7-stamped backup should restore successfully, got \(countAfterRestore) rows")
    }

    // MARK: - Test 5: Garbage store file is rejected

    @Test("Garbage Tenra.sqlite with valid metadata.json is rejected")
    func garbageStoreFileIsRejected() async throws {
        let (service, _, backupsRoot) = try makeService()

        // Create a fake backup directory by hand.
        let fakeDir = backupsRoot.appendingPathComponent("2026-01-01T00-00-00Z", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeDir, withIntermediateDirectories: true)

        // Write random bytes as the SQLite file.
        let garbage = Data(repeating: 0xFF, count: 1024)
        let garbageStoreURL = fakeDir.appendingPathComponent("Tenra.sqlite")
        try garbage.write(to: garbageStoreURL)

        // Write a valid-looking metadata.json.
        let fakeMetadata = BackupMetadata(
            id: UUID().uuidString,
            date: Date(),
            transactionCount: 0,
            accountCount: 0,
            categoryCount: 0,
            modelVersion: "v7",
            fileSize: Int64(garbage.count),
            appVersion: "1.0"
        )
        let metadataURL = fakeDir.appendingPathComponent("metadata.json")
        try JSONEncoder().encode(fakeMetadata).write(to: metadataURL)

        // Restore must throw (either .incompatibleVersion or the metadata-read error).
        var didThrow = false
        do {
            try await service.restoreBackup(fakeMetadata)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Restoring a garbage store file should throw, but it succeeded")
    }
}

