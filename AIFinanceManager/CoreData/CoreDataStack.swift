//
//  CoreDataStack.swift
//  AIFinanceManager
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

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CoreDataStack")

    // MARK: - Singleton

    nonisolated static let shared = CoreDataStack()

    /// Флаг доступности CoreData. При ошибке инициализации = false → приложение работает через UserDefaults fallback.
    /// nonisolated(unsafe): written once in loadPersistentStores callback, then only read — accepted race.
    nonisolated(unsafe) private(set) var isCoreDataAvailable: Bool = true

    /// Ошибка инициализации CoreData (для отображения пользователю)
    /// nonisolated(unsafe): written once in loadPersistentStores callback, then only read — accepted race.
    nonisolated(unsafe) private(set) var initializationError: String? = nil

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

        let container = NSPersistentContainer(name: "AIFinanceManager")

        // Configure container
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Protect financial data at rest: file is inaccessible while device is locked
        description?.setOption(FileProtectionType.complete as NSObject,
                                forKey: NSPersistentStoreFileProtectionKey)

        // Enable automatic lightweight migration
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        container.loadPersistentStores { [self] storeDescription, error in
            if let error = error as NSError? {
                CoreDataStack.logger.critical("Persistent store failed to load: \(error), \(error.userInfo)")
                self.isCoreDataAvailable = false
                if error.code == NSPersistentStoreIncompatibleVersionHashError ||
                   error.code == NSMigrationMissingSourceModelError {
                    self.initializationError = String(localized: "error.coredata.migrationFailed")
                } else {
                    self.initializationError = String(localized: "error.coredata.initializationFailed")
                }
            } else {
                CoreDataStack.logger.info("✅ [CoreDataStack] Persistent store loaded: \(storeDescription.url?.lastPathComponent ?? "unknown", privacy: .public)")
                CoreDataStack.logger.info("✅ [CoreDataStack] File protection: .complete enabled")
            }
        }

        // Automatic merge from parent context
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Use constraint merge policy to handle unique constraint violations
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Undo manager for view context (optional, can be disabled for performance)
        container.viewContext.undoManager = nil

        _persistentContainer = container
        return container
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
    func purgeHistory(olderThan days: Int = 7) {
        guard let cutoff = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) else { return }
        let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
        // viewContext is main-thread affined — must use perform for thread safety.
        viewContext.perform {
            do {
                try self.viewContext.execute(purgeRequest)
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

    /// Delete all data from persistent store (use for testing/debugging)
    nonisolated func resetAllData() throws {
        let coordinator = persistentContainer.persistentStoreCoordinator

        for store in coordinator.persistentStores {
            if let storeURL = store.url {
                try coordinator.destroyPersistentStore(at: storeURL, ofType: store.type, options: nil)
                // Restore all store options on the recreated store — passing nil would drop them.
                // Without re-applying these, persistent history tracking and remote change
                // notifications are silently disabled until the next app restart.
                let storeOptions: [String: Any] = [
                    NSPersistentStoreFileProtectionKey: FileProtectionType.complete,
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
                Logger(subsystem: "AIFinanceManager", category: "CoreDataStack").error("Error in performAndSave: \(error)")
            }
        }
    }
}
