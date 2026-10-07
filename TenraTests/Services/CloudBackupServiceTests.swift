//
//  CloudBackupServiceTests.swift
//  TenraTests
//
//  Tests for CloudBackupService backup/restore lifecycle.
//  Covers: derived model-version constant, createBackup stamping, round-trip
//  restore, legacy "v7"-stamped backup compatibility, garbage-file rejection,
//  self-contained snapshots, failed backups never listed, damaged backups refused
//  with the live store untouched, and pre-2026-10 raw-copy backups.
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
@Suite("CloudBackupServiceTests", .serialized, .sharedProcessState)
struct CloudBackupServiceTests {

    // MARK: - Fixture helpers

    /// Builds a real on-disk NSPersistentContainer in a unique temp directory.
    /// Returns (container, storeURL). Caller owns cleanup.
    private func makeOnDiskContainer() throws -> (NSPersistentContainer, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TenraTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("Tenra.sqlite")
        return (try makeContainer(at: storeURL), storeURL)
    }

    /// Opens (or creates) the store at `storeURL` with the production store options that
    /// matter here: lightweight migration on.
    private func makeContainer(at storeURL: URL) throws -> NSPersistentContainer {
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

        return container
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

    private func liveStoreURL(of stack: CoreDataStack) throws -> URL {
        try #require(stack.persistentContainer.persistentStoreCoordinator.persistentStores.first?.url)
    }

    /// The backup folder whose metadata.json carries `id`.
    private func backupDirectory(id: String, in backupsRoot: URL) throws -> URL {
        let dirs = try FileManager.default.contentsOfDirectory(
            at: backupsRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        let match = dirs.first { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("metadata.json")),
                  let metadata = try? JSONDecoder().decode(BackupMetadata.self, from: data) else { return false }
            return metadata.id == id
        }
        return try #require(match, "no backup folder for \(id)")
    }

    /// Writes a backup folder by hand, as an older app version (or a broken copy) left it.
    @discardableResult
    private func writeBackupFolder(
        named name: String,
        in backupsRoot: URL,
        store: Data?,
        date: Date = Date()
    ) throws -> BackupMetadata {
        let dir = backupsRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let store {
            try store.write(to: dir.appendingPathComponent("Tenra.sqlite"))
        }
        let metadata = BackupMetadata(
            id: UUID().uuidString, date: date, transactionCount: 0, accountCount: 0,
            categoryCount: 0, modelVersion: "v7", fileSize: Int64(store?.count ?? 0),
            appVersion: "1.3"
        )
        try JSONEncoder().encode(metadata).write(to: dir.appendingPathComponent("metadata.json"))
        return metadata
    }

    /// Restore must fail with `expected`, and leave the live store as it was.
    private func expectRestoreRefused(
        _ metadata: BackupMetadata,
        by service: CloudBackupService,
        stack: CoreDataStack,
        liveCount: Int,
        expected: (CoreDataStack.CloudBackupError) -> Bool
    ) async throws {
        do {
            try await service.restoreBackup(metadata)
            Issue.record("restore should have been refused")
        } catch let error as CoreDataStack.CloudBackupError {
            #expect(expected(error), "unexpected error: \(error)")
        }
        let container = stack.persistentContainer
        #expect(transactionCount(in: container) == liveCount, "live data must be untouched")
        // The live store is still attached and writable.
        seedTransactions(count: 1, in: container)
        #expect(transactionCount(in: container) == liveCount + 1)
        #expect(try restoreWorkDirectories(beside: liveStoreURL(of: stack)).isEmpty)
    }

    /// Leftovers of a restore next to the store; there must be none once it returns.
    private func restoreWorkDirectories(beside storeURL: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("RestoreWork-") }
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
        // The previous store kept aside during the swap, and the staged copy, are gone.
        #expect(try restoreWorkDirectories(beside: liveStoreURL(of: stack)).isEmpty)
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
        let (service, stack, backupsRoot) = try makeService()
        seedTransactions(count: 2, in: stack.persistentContainer)

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

        // Restore must throw before touching the live store (it used to delete it first).
        try await expectRestoreRefused(fakeMetadata, by: service, stack: stack, liveCount: 2) {
            if case .damagedBackup = $0 { return true }
            return false
        }
    }

    // MARK: - Consistent snapshot

    @Test("A backup is one self-contained Tenra.sqlite holding every saved row")
    func backupIsSelfContainedSnapshot() async throws {
        let (service, stack, backupsRoot) = try makeService()
        let container = stack.persistentContainer
        // Saved rows stay in the -wal until SQLite checkpoints it; the old copy of
        // Tenra.sqlite alone missed them.
        seedTransactions(count: 25, in: container)
        let scratchBefore = try scratchFolders()

        let metadata = try await service.createBackup(
            transactionCount: 25, accountCount: 0, categoryCount: 0
        )

        let backupDir = try backupDirectory(id: metadata.id, in: backupsRoot)
        let files = try FileManager.default.contentsOfDirectory(atPath: backupDir.path).sorted()
        #expect(files == ["Tenra.sqlite", "metadata.json"], "no -wal or -shm next to the snapshot")
        let backupStore = backupDir.appendingPathComponent("Tenra.sqlite")
        #expect(metadata.fileSize == PersistentStoreFiles.fileSize(of: backupStore))

        // Open the file on its own, as a restore on another device would.
        let isolatedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TenraIsolated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        let isolated = isolatedDir.appendingPathComponent("Tenra.sqlite")
        try FileManager.default.copyItem(at: backupStore, to: isolated)
        let reader = try makeContainer(at: isolated)
        #expect(transactionCount(in: reader) == 25)
        #expect(try scratchFolders() == scratchBefore, "the snapshot's scratch folder is removed")
    }

    /// The snapshot's scratch folders in the temporary directory.
    private func scratchFolders() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("TenraBackup-") })
    }

    @Test("A backup that can't be written throws and leaves nothing listed")
    func failedBackupThrowsAndIsNotListed() async throws {
        let (service, stack, backupsRoot) = try makeService()
        seedTransactions(count: 2, in: stack.persistentContainer)
        // A file where the backups folder should be: the backup folder can't be created.
        let blocked = backupsRoot.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: blocked)
        service.backupsRootOverride = blocked

        await #expect(throws: CoreDataStack.CloudBackupError.self) {
            _ = try await service.createBackup(transactionCount: 2, accountCount: 0, categoryCount: 0)
        }
        #expect(service.listBackups().isEmpty)
    }

    // MARK: - Restore safety

    @Test("A truncated backup is refused before the live store is touched")
    func truncatedBackupKeepsLiveData() async throws {
        let (service, stack, backupsRoot) = try makeService()
        let container = stack.persistentContainer
        seedTransactions(count: 3, in: container)
        let metadata = try await service.createBackup(
            transactionCount: 3, accountCount: 0, categoryCount: 0
        )
        seedTransactions(count: 2, in: container)

        let backupStore = try backupDirectory(id: metadata.id, in: backupsRoot)
            .appendingPathComponent("Tenra.sqlite")
        let handle = try FileHandle(forWritingTo: backupStore)
        try handle.truncate(atOffset: UInt64(PersistentStoreFiles.fileSize(of: backupStore) / 2))
        try handle.close()

        try await expectRestoreRefused(metadata, by: service, stack: stack, liveCount: 5) {
            if case .damagedBackup = $0 { return true }
            return false
        }
    }

    @Test("An empty backup file is refused, not opened as a new empty store")
    func emptyBackupFileIsRefused() async throws {
        let (service, stack, backupsRoot) = try makeService()
        seedTransactions(count: 2, in: stack.persistentContainer)
        let metadata = try writeBackupFolder(named: "2026-01-02T00-00-00Z", in: backupsRoot, store: Data())

        try await expectRestoreRefused(metadata, by: service, stack: stack, liveCount: 2) {
            if case .damagedBackup = $0 { return true }
            return false
        }
    }

    @Test("A backup folder without its store file is refused")
    func missingBackupStoreIsRefused() async throws {
        let (service, stack, backupsRoot) = try makeService()
        seedTransactions(count: 2, in: stack.persistentContainer)
        let metadata = try writeBackupFolder(named: "2026-01-03T00-00-00Z", in: backupsRoot, store: nil)

        try await expectRestoreRefused(metadata, by: service, stack: stack, liveCount: 2) {
            if case .damagedBackup = $0 { return true }
            return false
        }
    }

    @Test("A backup in the pre-2026-10 format (.sqlite, -wal, -shm copied raw) restores every row")
    func legacyRawCopyBackupRestores() async throws {
        let (service, stack, backupsRoot) = try makeService()
        let container = stack.persistentContainer
        seedTransactions(count: 4, in: container)
        let storeURL = try liveStoreURL(of: stack)

        // What createBackup used to do: copy the three files while the store is open.
        let legacy = try writeBackupFolder(named: "2026-09-01T10-00-00Z", in: backupsRoot, store: nil)
        let legacyDir = try backupDirectory(id: legacy.id, in: backupsRoot)
        let legacyStore = legacyDir.appendingPathComponent("Tenra.sqlite")
        for (source, target) in zip(PersistentStoreFiles.allFileURLs(ofStore: storeURL),
                                    PersistentStoreFiles.allFileURLs(ofStore: legacyStore))
        where FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.copyItem(at: source, to: target)
        }

        seedTransactions(count: 3, in: container)
        try await service.restoreBackup(legacy)

        #expect(transactionCount(in: container) == 4)
    }
}

