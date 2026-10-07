//
//  CoreDataSaveCoordinator.swift
//  Tenra
//
//  Created on 2026
//
//  Runs the repositories' background saves, one at a time per operation name.
//
//  Two kinds of save share this path:
//  • A ticketed save (`performSave(operation:ticket:)`) writes a whole table: the newest
//    snapshot replaces every older one. Saves of one operation run in ticket order. A save
//    still waiting when a newer one arrives is skipped, and its caller waits for the newer
//    one, which carries its data too. A ticket older than one already started is skipped
//    the same way. Take the ticket with `nextTicket()` at the moment the data is captured,
//    before hopping to a background task: background tasks can reach this actor in any order.
//  • An unticketed save runs after the saves of the same name already queued, in arrival
//    order. Use it for writes that do not replace each other.
//
//  No save is dropped. The old guard threw `savingInProgress` at a second save of the same
//  name while the first ran, every caller swallowed it, and the newer data was lost (a
//  user's account edit landing while the deposits pass saved accounts, for example).
//

import Foundation
import CoreData

/// Hands out increasing save tickets, from any thread.
nonisolated final class SaveTicketCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var last: UInt64 = 0

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        last &+= 1
        return last
    }
}

/// Actor that coordinates all Core Data save operations.
actor CoreDataSaveCoordinator {

    // MARK: - Properties

    private let stack: CoreDataStack
    private let tickets = SaveTicketCounter()

    init(stack: CoreDataStack = CoreDataStack.shared) {
        self.stack = stack
    }

    /// The saves of one operation name.
    private struct Lane {
        /// Newest ticket started or queued. Ticketed lanes keep it after going idle, so a
        /// late save carrying an older snapshot is still recognised as older.
        var newestTicket: UInt64 = 0
        /// The last save started or queued; the next save of this name runs after it.
        /// The value is `false` when the save was skipped for a newer one.
        var tail: Task<Bool, Error>?
        /// Identifies `tail`, so a finishing save knows whether it is still the last one.
        var tailID: UInt64 = 0
        var isTicketed = false
    }

    private var lanes: [String: Lane] = [:]

    // MARK: - Save Operations

    /// A ticket for a whole-table save whose data the caller is capturing now. Call it
    /// synchronously, in the same step that captures the data.
    nonisolated func nextTicket() -> UInt64 {
        tickets.next()
    }

    /// Performs `work` on a fresh background context and saves it, after every earlier save
    /// of the same `operation`. Returns once this data, or a newer snapshot that carries it,
    /// is on disk.
    /// - Parameters:
    ///   - operation: Saves with the same name run one at a time.
    ///   - ticket: Pass one (from `nextTicket()`) when `work` replaces what older saves of
    ///     this operation wrote, so only the newest snapshot is written. Leave it `nil` for
    ///     writes that must each run.
    ///   - work: The work to perform in the context.
    /// - Throws: `SaveError.saveFailed` when the save (or the newer one that carried this
    ///   data) fails.
    func performSave(
        operation: String,
        ticket: UInt64? = nil,
        work: @escaping (NSManagedObjectContext) throws -> Void
    ) async throws {
        var lane = lanes[operation] ?? Lane()
        let callID = tickets.next()

        if let ticket {
            lane.isTicketed = true
            guard ticket > lane.newestTicket else {
                // A newer snapshot of this table is queued, running, or written.
                lanes[operation] = lane
                try await waitForNewestSave(of: operation)
                return
            }
            lane.newestTicket = ticket
        }

        let previous = lane.tail
        let task = Task<Bool, Error> {
            _ = await previous?.result
            // Skipped when a newer snapshot queued up behind this one meanwhile: it runs next.
            if let ticket, self.lanes[operation]?.newestTicket != ticket {
                return false
            }
            try await self.save(operation: operation, work: work)
            return true
        }
        lane.tail = task
        lane.tailID = callID
        lanes[operation] = lane

        let result = await task.result
        retire(operation: operation, callID: callID)

        if try result.get() == false {
            // Skipped for a newer save of this table: return once that one is on disk.
            try await waitForNewestSave(of: operation)
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

    // MARK: - Status

    /// Newest ticket started or queued for `operation` (0 when none). For diagnostics and tests.
    func newestTicket(of operation: String) -> UInt64 {
        lanes[operation]?.newestTicket ?? 0
    }

    // MARK: - Private

    private func save(
        operation: String,
        work: @escaping (NSManagedObjectContext) throws -> Void
    ) async throws {
        // newBackgroundContext() is thread-safe (container already initialized) — no MainActor hop needed
        let context = stack.newBackgroundContext()

        do {
            try await context.perform {
                try work(context)

                if context.hasChanges {
                    do {
                        try context.save()
                    } catch let error as NSError {
                        if error.code == NSManagedObjectMergeError {
                            self.handleMergeConflict(context: context)
                        }
                        throw error
                    }
                }
            }
        } catch {
            throw SaveError.saveFailed(operation: operation, underlyingError: error)
        }
    }

    /// Waits until a save of `operation` newer than the caller's has written. The lane's
    /// last save is always the newest; when it was itself skipped, a newer one replaced it
    /// as the last, so the loop moves forward and ends.
    private func waitForNewestSave(of operation: String) async throws {
        while let newest = lanes[operation]?.tail {
            if try await newest.value { return }
        }
    }

    /// Forgets the lane's last save once it finished. An unticketed lane is removed (its
    /// names are often unique per call); a ticketed one keeps its newest ticket.
    private func retire(operation: String, callID: UInt64) {
        guard var lane = lanes[operation], lane.tailID == callID else { return }
        if lane.isTicketed {
            lane.tail = nil
            lanes[operation] = lane
        } else {
            lanes.removeValue(forKey: operation)
        }
    }

    // MARK: - Conflict Resolution

    private nonisolated func handleMergeConflict(context: NSManagedObjectContext) {
        // After context.reset(), hasChanges is always false — retry is impossible.
        // The merge policy (NSMergeByPropertyObjectTrumpMergePolicy) on the context
        // should handle most conflicts automatically. If we still get here, the caller
        // rethrows so the failure is logged instead of passing for a save (the old code
        // reset and returned, which reported the lost write as a success).
        context.reset()
    }
}

// MARK: - Supporting Types

/// Error types for save operations
enum SaveError: LocalizedError {
    case saveFailed(operation: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let operation, let error):
            return "Save operation '\(operation)' failed: \(error.localizedDescription)"
        }
    }
}
