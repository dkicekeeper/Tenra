//
//  CoreDataStack+Backup.swift
//  Tenra
//
//  Core Data side of backup and restore: a consistent single-file snapshot of the live
//  store, and the checks a store copy passes before it counts as a backup or may replace
//  the live store. The file moves are PersistentStoreFiles; the swap itself is
//  CoreDataStack.swapStore(from:), which needs the container lock.
//

import Foundation
import CoreData
import os

extension CoreDataStack {

    /// For the backup and restore code, which runs off the main actor (the class's own
    /// logger is main-actor isolated).
    nonisolated static let backupLogger = Logger(subsystem: "Tenra", category: "CoreDataStack")

    /// Why a store copy was refused. Callers wrap it in `CloudBackupError`.
    nonisolated enum StoreCopyError: LocalizedError {
        /// Empty, or not a Core Data store at all. Core Data would open such a file as a
        /// new, empty store, and restoring it would wipe the user's data.
        case notAStore
        /// The snapshot doesn't carry the live store's model.
        case unexpectedModel

        var errorDescription: String? {
            switch self {
            case .notAStore: return "The file is not a Core Data store"
            case .unexpectedModel: return "The copy does not match the current data model"
            }
        }
    }

    // MARK: - Snapshot

    /// Writes a consistent copy of the live store to `destinationURL` as one self-contained
    /// SQLite file, then proves the copy is sound (`validateStoreCopy`).
    ///
    /// Backups used to copy `Tenra.sqlite` and then its -wal with FileManager: the newest
    /// saves can live only in the -wal, and a save landing between the two copies paired a
    /// main file with a WAL from another moment. `replacePersistentStore` copies through
    /// SQLite, which honours its locks and reads one consistent state, WAL included, while
    /// the app keeps using the store. Blocks: call it off the main thread.
    nonisolated func snapshotStore(to destinationURL: URL) throws {
        let container = persistentContainer
        guard let store = container.persistentStoreCoordinator.persistentStores.first,
              let storeURL = store.url else { throw CloudBackupError.noActiveStore }
        let model = container.managedObjectModel
        let singleFileOptions = Self.singleFileOptions(from: store.options)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.replacePersistentStore(
            at: destinationURL,
            destinationOptions: singleFileOptions,
            withPersistentStoreFrom: storeURL,
            sourceOptions: Self.copyOptions(from: store.options),
            type: .sqlite
        )
        let metadata = try Self.storeMetadata(ofCopyAt: destinationURL)
        guard model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
            throw StoreCopyError.unexpectedModel
        }
        // Opening it in rollback-journal mode also folds anything SQLite left in a -wal
        // into the main file.
        try Self.validateStoreCopy(at: destinationURL, model: model, options: singleFileOptions)
    }

    // MARK: - Checks

    /// The store metadata of a copy. Refuses a file that is empty or not a Core Data store.
    nonisolated static func storeMetadata(ofCopyAt url: URL) throws -> [String: Any] {
        guard PersistentStoreFiles.fileSize(of: url) > 0 else { throw StoreCopyError.notAStore }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any], !hashes.isEmpty else {
            throw StoreCopyError.notAStore
        }
        return metadata
    }

    /// Whether the current model opens a store with this metadata: directly, or after a
    /// lightweight migration from an older model version bundled with the app. A store
    /// written by a newer app version can't be opened.
    nonisolated static func canOpenStore(withMetadata metadata: [String: Any], model: NSManagedObjectModel) -> Bool {
        model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
            || NSManagedObjectModel.mergedModel(from: [.main], forStoreMetadata: metadata) != nil
    }

    /// Proves a store copy is sound: it is a Core Data store, SQLite's page check passes,
    /// and Core Data opens it with `model` and counts every entity. Opening migrates a copy
    /// made by an older app version in place, which is why this only ever runs on a copy.
    /// Returns the row count per entity name.
    @discardableResult
    nonisolated static func validateStoreCopy(
        at url: URL,
        model: NSManagedObjectModel,
        options: [AnyHashable: Any]
    ) throws -> [String: Int] {
        _ = try storeMetadata(ofCopyAt: url)
        try PersistentStoreFiles.checkIntegrity(ofDatabaseAt: url)
        // The pool releases the throwaway coordinator, and its SQLite connection, before the
        // caller moves or copies the file.
        return try autoreleasepool {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
            defer { try? coordinator.remove(store) }
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            return try context.performAndWait {
                var counts: [String: Int] = [:]
                for name in model.entities.compactMap(\.name) {
                    counts[name] = try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: name))
                }
                return counts
            }
        }
    }

    // MARK: - Options

    /// The live store's options, for opening a copy of it. Persistent history tracking must
    /// stay as it is: a store that had it, opened without it, is forced read-only.
    /// Remote-change notifications are left out, nothing observes a scratch copy.
    nonisolated static func copyOptions(from options: [AnyHashable: Any]?) -> [AnyHashable: Any] {
        var result = options ?? [:]
        result[NSPersistentStoreRemoteChangeNotificationPostOptionKey] = nil
        return result
    }

    /// `copyOptions` in rollback-journal mode, so the copy is one file with no -wal.
    nonisolated static func singleFileOptions(from options: [AnyHashable: Any]?) -> [AnyHashable: Any] {
        var result = copyOptions(from: options)
        var pragmas = result[NSSQLitePragmasOption] as? [String: Any] ?? [:]
        pragmas["journal_mode"] = "DELETE"
        result[NSSQLitePragmasOption] = pragmas
        return result
    }
}
