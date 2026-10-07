//
//  CoreDataStack.swift
//  Tenra
//
//  Created on 2026
//
//  Core Data Stack for managing persistent storage

import Foundation
import CoreData
import UIKit
import os

/// Core Data Stack - Singleton for managing Core Data
final class CoreDataStack: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CoreDataStack")

    // MARK: - Singleton

    nonisolated static let shared = CoreDataStack()

    /// Why the store could not be opened; nil while it is open (or not loaded yet).
    /// Written in the `loadPersistentStores` callback, which runs synchronously inside
    /// `createAndLoadContainer` while `containerLock` is held; read under the same lock
    /// (`openStoreIfNeeded`, `isCoreDataAvailable`), so a reader never sees a stale value.
    /// A failed store is never worked around: TenraApp shows a blocking error screen and
    /// builds nothing that could read, write, back up or replace it (no UserDefaults fallback).
    private nonisolated(unsafe) var _loadFailure: StoreLoadFailure?

    /// False once loading the store has failed. Loads the store first if needed.
    nonisolated var isCoreDataAvailable: Bool { openStoreIfNeeded() == nil }

    /// Lock protecting one-time initialization of _persistentContainer.
    /// Swift `lazy var` is NOT thread-safe. preWarm() accesses persistentContainer from
    /// Task.detached while the main thread accesses it via AppCoordinator.initialize().
    /// Without this lock, two NSPersistentContainer instances can be created — each with
    /// its own NSPersistentStoreCoordinator but pointing at the same SQLite file. Objects
    /// registered in one coordinator become "not reachable" from the other, causing:
    /// "persistent store is not reachable from this NSManagedObjectContext's coordinator".
    private let containerLock = NSLock()
    private nonisolated(unsafe) var _persistentContainer: NSPersistentContainer?

    private init() {
        setupNotifications()
    }

    /// Testing-only initializer: wraps an already-loaded NSPersistentContainer so tests
    /// can inject an in-memory store without touching CoreDataStack.shared.
    /// NOT for production use — init is internal so it is only callable from the same module
    /// and from `@testable import Tenra` test targets.
    init(container: NSPersistentContainer) {
        self._persistentContainer = container
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notifications

    private func setupNotifications() {
        // Save context when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveOnBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        // Save context before app terminates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveOnTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func saveOnBackground() {
        saveContextSync()
    }

    @objc private func saveOnTerminate() {
        saveContextSync()
    }

    private func saveContextSync() {
        let context = viewContext
        context.performAndWait {
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                CoreDataStack.logger.error("Error saving context on lifecycle event: \(error as NSError)")
            }
        }
    }

    // MARK: - Pre-Warm

    /// Touch persistentContainer on a background thread so loadPersistentStores()
    /// runs off MainActor. Call from AppDelegate.didFinishLaunchingWithOptions —
    /// before AppCoordinator is created.
    func preWarm() {
        Task.detached(priority: .userInitiated) {
            _ = CoreDataStack.shared.persistentContainer
        }
    }

    // MARK: - Container Creation

    /// Creates and loads a local-only persistent container. iCloud/CloudKit sync was
    /// removed 2026-04-22 after `HistoryExpired` events caused data loss on restart.
    /// Call with `containerLock` held. `model`: reuse an already loaded model (a retry), so the
    /// process never holds two models claiming the same NSManagedObject subclasses.
    private nonisolated func createAndLoadContainer(model: NSManagedObjectModel? = nil) -> NSPersistentContainer {
        let container = model.map { NSPersistentContainer(name: "Tenra", managedObjectModel: $0) }
            ?? NSPersistentContainer(name: "Tenra")
        _loadFailure = nil

        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // .completeUntilFirstUserAuthentication keeps the store accessible during
        // background fetches (e.g. background tasks). `.complete` would block access
        // while the device is locked.
        description?.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                forKey: NSPersistentStoreFileProtectionKey)

        // Enable automatic lightweight migration
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        // SQLite stores load synchronously (shouldAddStoreAsynchronously is false), so the
        // callback runs before loadPersistentStores returns, still under containerLock.
        container.loadPersistentStores { [self] storeDescription, error in
            if let error = error as NSError? {
                let failure = StoreLoadFailure(error: error)
                CoreDataStack.logger.critical("Persistent store failed to load (\(failure.kind.rawValue, privacy: .public), \(failure.reference, privacy: .public)): \(error), \(error.userInfo)")
                self._loadFailure = failure
            } else {
                CoreDataStack.logger.info("✅ [CoreDataStack] Persistent store loaded: \(storeDescription.url?.lastPathComponent ?? "unknown", privacy: .public)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil

        return container
    }

    // MARK: - Persistent Container

    /// Thread-safe accessor for the persistent container.
    /// Uses NSLock to guarantee exactly ONE NSPersistentContainer is created, even when
    /// preWarm() (background thread) and AppCoordinator.initialize() (main thread) race.
    nonisolated var persistentContainer: NSPersistentContainer {
        containerLock.lock()
        defer { containerLock.unlock() }

        if let existing = _persistentContainer {
            return existing
        }

        let container = createAndLoadContainer()
        _persistentContainer = container
        return container
    }

    /// Opens the store if this process hasn't yet, and says why it could not be opened
    /// (nil = open). Blocks while the store loads, migrations included: call it off the main
    /// thread. Every launch path checks this before building anything over the store.
    nonisolated func openStoreIfNeeded() -> StoreLoadFailure? {
        _ = persistentContainer
        containerLock.lock()
        defer { containerLock.unlock() }
        return _loadFailure
    }

    /// Loads the store again after a failed attempt (the device was still locked, storage was
    /// full, a transient I/O error). Never deletes, moves or rewrites the store file, and reuses
    /// the model already loaded. Returns the new failure, nil once the store is open.
    /// Blocking, like `openStoreIfNeeded`.
    nonisolated func retryOpeningStore() -> StoreLoadFailure? {
        containerLock.lock()
        defer { containerLock.unlock() }
        if _persistentContainer != nil, _loadFailure == nil { return nil }
        _persistentContainer = createAndLoadContainer(model: _persistentContainer?.managedObjectModel)
        return _loadFailure
    }

    /// URL of the primary persistent store file.
    nonisolated var persistentStoreURL: URL? {
        persistentContainer.persistentStoreDescriptions.first?.url
    }

    // MARK: - Contexts

    /// Main view context - use for UI operations on main thread
    nonisolated var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    /// Create new background context for heavy operations
    nonisolated func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }

    // MARK: - Save Operations

    /// Save context if it has changes
    /// - Parameter context: The context to save
    func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }

        context.perform {
            do {
                try context.save()
            } catch {
                CoreDataStack.logger.error("Error saving context: \(error as NSError)")
            }
        }
    }

    /// Save context synchronously (use carefully, can block thread)
    /// - Parameter context: The context to save
    func saveContextSync(_ context: NSManagedObjectContext) throws {
        try context.performAndWait {
            guard context.hasChanges else { return }
            try context.save()
        }
    }

    // MARK: - Batch Operations

    /// Execute batch delete request
    /// - Parameter fetchRequest: The fetch request defining objects to delete
    func batchDelete<T: NSManagedObject>(_ fetchRequest: NSFetchRequest<T>) throws {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
        deleteRequest.resultType = .resultTypeObjectIDs

        try viewContext.performAndWait {
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            let objectIDArray = result?.result as? [NSManagedObjectID] ?? []

            // Merge changes to view context
            let changes = [NSDeletedObjectsKey: objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        }
    }

    /// Execute batch update request
    /// - Parameter batchUpdate: The batch update request
    func batchUpdate(_ batchUpdate: NSBatchUpdateRequest) throws {
        batchUpdate.resultType = .updatedObjectIDsResultType

        try viewContext.performAndWait {
            let result = try viewContext.execute(batchUpdate) as? NSBatchUpdateResult
            let objectIDArray = result?.result as? [NSManagedObjectID] ?? []

            // Merge changes to view context
            let changes = [NSUpdatedObjectsKey: objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        }
    }

    /// Merge inserted object IDs from an NSBatchInsertRequest result into viewContext.
    /// Must be called after executing NSBatchInsertRequest to keep viewContext in sync.
    /// NSBatchInsertRequest writes directly to SQLite and bypasses the managed object
    /// lifecycle, so automaticallyMergesChangesFromParent does NOT propagate the changes.
    func mergeBatchInsertResult(_ result: NSBatchInsertResult?) {
        guard let objectIDs = result?.result as? [NSManagedObjectID],
              !objectIDs.isEmpty else { return }
        let changes = [NSInsertedObjectIDsKey: objectIDs]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
    }

    // MARK: - Persistent History

    /// Purge persistent history older than `days` days.
    /// Called once per launch from a background task to prevent unbounded DB growth.
    ///
    /// Runs on a fresh `newBackgroundContext()` — viewContext.perform { } would block
    /// MainActor for the entire purge (observed 1–2 s on databases with heavy CSV
    /// import history), freezing the UI right after `isFullyInitialized = true` flips.
    func purgeHistory(olderThan days: Int = 7) {
        guard let cutoff = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) else { return }
        let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
        let bgContext = newBackgroundContext()
        bgContext.perform {
            do {
                try bgContext.execute(purgeRequest)
                CoreDataStack.logger.info("Purged persistent history older than \(days) days")
            } catch {
                CoreDataStack.logger.error("Failed to purge persistent history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reset

    /// Posted synchronously on the main thread after the persistent store has been
    /// destroyed and recreated. Observers (e.g. NSFetchedResultsController holders)
    /// must tear down stale references and re-fetch from the new store.
    nonisolated static let storeDidResetNotification = Notification.Name("CoreDataStack.storeDidReset")

    /// Tears down the current container and creates a fresh one, picking up any changes
    /// to iCloudSyncEnabled. Posts storeDidResetNotification so FRC holders can rebuild.
    func reloadContainer() {
        containerLock.lock()
        if let container = _persistentContainer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
        let newContainer = createAndLoadContainer()
        _persistentContainer = newContainer
        containerLock.unlock()
        NotificationCenter.default.post(name: Self.storeDidResetNotification, object: self)
    }

    /// Delete all data from persistent store (use for testing/debugging)
    nonisolated func resetAllData() throws {
        let coordinator = persistentContainer.persistentStoreCoordinator

        for store in coordinator.persistentStores {
            if let storeURL = store.url {
                try coordinator.destroyPersistentStore(at: storeURL, ofType: store.type, options: nil)
                // Restore all store options on the recreated store — passing nil would drop them.
                // Without re-applying these, persistent history tracking and remote change
                // notifications are silently disabled until the next app restart.
                // Use .completeUntilFirstUserAuthentication to allow background sync access.
                let storeOptions: [String: Any] = [
                    NSPersistentStoreFileProtectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                    NSPersistentHistoryTrackingKey: true as NSNumber,
                    NSPersistentStoreRemoteChangeNotificationPostOptionKey: true as NSNumber
                ]
                try coordinator.addPersistentStore(ofType: store.type, configurationName: nil, at: storeURL, options: storeOptions)
            }
        }

        // CRITICAL: destroyPersistentStore+addPersistentStore creates a new store with
        // a different UUID. Existing NSManagedObject faults in viewContext (and any FRC
        // backed by it) still reference the OLD store UUID. Any access to those faults
        // crashes with "persistent store is not reachable from this coordinator".
        // reset() evicts all registered objects so no zombie faults remain.
        viewContext.reset()

        // Notify FRC holders (TransactionPaginationController) to tear down and
        // re-create their controllers on the new store. Must be synchronous so the
        // FRC is rebuilt BEFORE any subsequent save+merge triggers its delegate.
        NotificationCenter.default.post(name: Self.storeDidResetNotification, object: self)
    }

    // MARK: - Store Swap

    enum CloudBackupError: Error, LocalizedError {
        case noActiveStore
        case copyFailed(Error)
        case incompatibleVersion(String)
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .noActiveStore: return String(localized: "error.backup.noActiveStore")
            case .copyFailed(let error): return String(localized: "error.backup.copyFailed") + ": \(error.localizedDescription)"
            case .incompatibleVersion(let version): return String(localized: "error.backup.incompatibleVersion") + " (\(version))"
            case .iCloudUnavailable: return String(localized: "error.backup.iCloudUnavailable")
            }
        }
    }

    /// Replaces the current persistent store with a backup file. Used for restoring
    /// from cloud backups. Posts storeDidResetNotification on the main thread on success.
    ///
    /// **Threading**: This method blocks for the duration of file I/O + PSC.add (can be
    /// hundreds of ms or more). It MUST be called from a background thread (e.g. via
    /// `Task.detached`). Calling it from the main thread will freeze the UI and trigger
    /// the watchdog. The viewContext mutations are dispatched onto the main queue
    /// internally via `performAndWait`.
    nonisolated func swapStore(from backupURL: URL) throws {
        containerLock.lock()
        defer { containerLock.unlock() }

        guard let container = _persistentContainer,
              let store = container.persistentStoreCoordinator.persistentStores.first,
              let storeURL = store.url else { throw CloudBackupError.noActiveStore }

        let options = store.options as? [String: Any]
        let viewContext = container.viewContext

        // Drop all registered objects on viewContext BEFORE removing the store —
        // any zombie fault accessed after the store is gone would crash with
        // "persistent store is not reachable from this coordinator".
        viewContext.performAndWait { viewContext.reset() }

        try container.persistentStoreCoordinator.remove(store)

        let fm = FileManager.default
        if fm.fileExists(atPath: storeURL.path) { try fm.removeItem(at: storeURL) }
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        try? fm.removeItem(at: walURL)
        try? fm.removeItem(at: shmURL)

        do {
            try fm.copyItem(at: backupURL, to: storeURL)
            // Also copy WAL and SHM from the backup directory if present
            let backupWalURL = URL(fileURLWithPath: backupURL.path + "-wal")
            let backupShmURL = URL(fileURLWithPath: backupURL.path + "-shm")
            if fm.fileExists(atPath: backupWalURL.path) {
                try? fm.copyItem(at: backupWalURL, to: walURL)
            }
            if fm.fileExists(atPath: backupShmURL.path) {
                try? fm.copyItem(at: backupShmURL, to: shmURL)
            }
        } catch {
            // Recovery: re-add the store at the original URL (now empty) to avoid a crash
            _ = try? container.persistentStoreCoordinator.addPersistentStore(type: .sqlite, at: storeURL, options: options)
            throw CloudBackupError.copyFailed(error)
        }

        _ = try container.persistentStoreCoordinator.addPersistentStore(type: .sqlite, at: storeURL, options: options)

        // Reset again so the viewContext picks up the new store's row cache.
        viewContext.performAndWait { viewContext.reset() }

        // Notify FRC holders on the main thread (asynchronously) so SwiftUI gets a
        // render frame between the swap completing and the FRC re-fetching.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.storeDidResetNotification, object: self)
        }
    }

    // MARK: - Performance Monitoring

    /// Get persistent store file size
    var storeSize: String {
        guard let storeURL = persistentContainer.persistentStoreDescriptions.first?.url else {
            return "Unknown"
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            CoreDataStack.logger.error("Error getting store size: \(error)")
        }

        return "Unknown"
    }
}

// MARK: - Convenience Extensions

extension NSManagedObjectContext {

    /// Perform operation and save if successful
    func performAndSave(_ block: @escaping () throws -> Void) {
        perform {
            do {
                try block()
                if self.hasChanges {
                    try self.save()
                }
            } catch {
                Logger(subsystem: "Tenra", category: "CoreDataStack").error("Error in performAndSave: \(error)")
            }
        }
    }
}
