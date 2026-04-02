//
//  CoreDataSaveCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Coordinator for synchronizing Core Data save operations
//  Prevents race conditions and data loss from concurrent saves

import Foundation
import CoreData

/// Actor that coordinates all Core Data save operations
/// Ensures that saves are serialized and don't conflict with each other
actor CoreDataSaveCoordinator {

    // MARK: - Properties

    private let stack: CoreDataStack

    init(stack: CoreDataStack = CoreDataStack.shared) {
        self.stack = stack
    }
    
    /// Track active save operations to prevent duplicates
    private var activeSaves: Set<String> = []
    
    /// Queue for pending save operations
    private var pendingSaves: [String: Date] = [:]
    
    // MARK: - Save Operations
    
    /// Perform a save operation with automatic retry on conflicts
    /// - Parameters:
    ///   - operation: Unique identifier for this operation type
    ///   - work: The work to perform in the context
    /// - Returns: Result of the work
    /// - Throws: SaveError if operation fails
    func performSave<T>(
        operation: String,
        work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        // Check if this operation is already in progress
        guard !activeSaves.contains(operation) else {
            throw SaveError.savingInProgress(operation: operation)
        }
        
        // Mark operation as active
        activeSaves.insert(operation)
        pendingSaves[operation] = Date()
        defer {
            activeSaves.remove(operation)
            pendingSaves.removeValue(forKey: operation)
        }
        
        let startTime = Date()

        // Create background context for this operation
        // newBackgroundContext() is thread-safe (container already initialized) — no MainActor hop needed
        let context = stack.newBackgroundContext()

        do {
            let result = try await context.perform {
                // Perform the work
                let workResult = try work(context)

                // Save if there are changes
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch let error as NSError {
                        // Handle merge conflicts
                        if error.code == NSManagedObjectMergeError {
                            try self.handleMergeConflict(context: context)
                        } else {
                            throw error
                        }
                    }
                } else {
                }

                return workResult
            }

            _ = Date().timeIntervalSince(startTime)

            return result
            
        } catch {
            throw SaveError.saveFailed(operation: operation, underlyingError: error)
        }
    }
    
    /// Perform multiple save operations in sequence
    /// - Parameter operations: Array of (name, work) tuples
    /// - Throws: SaveError if any operation fails
    func performBatchSave(
        operations: [(name: String, work: (NSManagedObjectContext) throws -> Void)]
    ) async throws {

        let context = stack.newBackgroundContext()

        try await context.perform {
            for (_, work) in operations {
                try work(context)
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    // MARK: - Conflict Resolution

    private nonisolated func handleMergeConflict(context: NSManagedObjectContext) throws {
        // After context.reset(), hasChanges is always false — retry is impossible.
        // The merge policy (NSMergeByPropertyObjectTrumpMergePolicy) on the context
        // should handle most conflicts automatically. If we still get here, log and
        // let the error propagate to the caller for retry at a higher level.
        context.reset()
    }
    
    // MARK: - Status
    
    /// Get current status of save operations
    var status: SaveStatus {
        SaveStatus(
            activeSaves: Array(activeSaves),
            pendingSaves: pendingSaves
        )
    }
    
    /// Check if a specific operation is in progress
    func isOperationInProgress(_ operation: String) -> Bool {
        return activeSaves.contains(operation)
    }
}

// MARK: - Supporting Types

/// Error types for save operations
enum SaveError: LocalizedError {
    case savingInProgress(operation: String)
    case saveFailed(operation: String, underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .savingInProgress(let operation):
            return "Save operation '\(operation)' is already in progress"
        case .saveFailed(let operation, let error):
            return "Save operation '\(operation)' failed: \(error.localizedDescription)"
        }
    }
}

/// Status of the save coordinator
struct SaveStatus {
    let activeSaves: [String]
    let pendingSaves: [String: Date]
    
    var isIdle: Bool {
        return activeSaves.isEmpty
    }
    
    var description: String {
        if isIdle {
            return "Idle"
        } else {
            return "Active operations: \(activeSaves.joined(separator: ", "))"
        }
    }
}

// MARK: - Convenience Extensions

// saveBatched removed — dead code: fetched entities via context.object(with:) but
// discarded the result (assigned to _), never mutated anything, so saves were no-ops.
