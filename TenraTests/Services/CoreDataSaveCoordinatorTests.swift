//
//  CoreDataSaveCoordinatorTests.swift
//  TenraTests
//
//  Pins that the save coordinator never drops a save. It used to throw
//  `savingInProgress` at a second save of the same name while the first ran, and
//  every repository swallowed that error: a user's account edit landing while the
//  deposits pass saved accounts was lost. Same-name saves now run one at a time; a
//  ticketed (whole-table) save still waiting when a newer one arrives is skipped,
//  because the newer snapshot carries its data.
//
//  `.serialized` + `.sharedProcessState`: in-memory containers named "Tenra".
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@Suite(.serialized, .sharedProcessState)
struct CoreDataSaveCoordinatorTests {

    // MARK: - Fixtures

    private func makeStack() throws -> (CoreDataStack, NSPersistentContainer) {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return (CoreDataStack(container: container), container)
    }

    /// Order in which save work ran.
    private final class WorkLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) { lock.withLock { entries.append(entry) } }
        var values: [String] { lock.withLock { entries } }
    }

    /// Holds the first save inside its work until the test has queued the others.
    private final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var entered = false

        func block() {
            lock.withLock { entered = true }
            _ = semaphore.wait(timeout: .now() + 10)
        }
        var isBlocked: Bool { lock.withLock { entered } }
        func open() { semaphore.signal() }
    }

    /// Reads through a fresh private-queue context: the suite is not on the main actor,
    /// so the main-queue viewContext is off limits.
    private func persistedAccountIds(in container: NSPersistentContainer) -> [String] {
        let context = container.newBackgroundContext()
        var ids: [String] = []
        context.performAndWait {
            ids = (try? context.fetch(AccountEntity.fetchRequest()))?.compactMap(\.id) ?? []
        }
        return ids
    }

    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    // MARK: - Ticketed (whole-table) saves

    @Test("A save of the same table queued during another runs after it; a superseded one is skipped")
    func queuedSavesCoalesceToTheNewest() async throws {
        let (stack, _) = try makeStack()
        let coordinator = CoreDataSaveCoordinator(stack: stack)
        let log = WorkLog()
        let gate = Gate()
        let first = coordinator.nextTicket()
        let second = coordinator.nextTicket()
        let third = coordinator.nextTicket()

        let running = Task {
            try await coordinator.performSave(operation: "table", ticket: first) { _ in
                gate.block()
                log.append("first")
            }
        }
        #expect(await waitUntil { gate.isBlocked })

        let superseded = Task {
            try await coordinator.performSave(operation: "table", ticket: second) { _ in log.append("second") }
        }
        #expect(await waitUntil { await coordinator.newestTicket(of: "table") == second })
        let newest = Task {
            try await coordinator.performSave(operation: "table", ticket: third) { _ in log.append("third") }
        }
        #expect(await waitUntil { await coordinator.newestTicket(of: "table") == third })

        gate.open()
        // Nobody is told "already in progress": every caller returns normally.
        try await running.value
        try await superseded.value
        try await newest.value

        #expect(log.values == ["first", "third"])
    }

    @Test("An older snapshot that reaches the coordinator after a newer one is not written")
    func lateOlderTicketIsSkipped() async throws {
        let (stack, _) = try makeStack()
        let coordinator = CoreDataSaveCoordinator(stack: stack)
        let log = WorkLog()
        // Taken in this order, as the data was captured...
        let older = coordinator.nextTicket()
        let newer = coordinator.nextTicket()

        // ...but the background tasks arrive the other way round.
        try await coordinator.performSave(operation: "table", ticket: newer) { _ in log.append("newer") }
        try await coordinator.performSave(operation: "table", ticket: older) { _ in log.append("older") }

        #expect(log.values == ["newer"])
    }

    // MARK: - Unticketed saves

    @Test("Saves without a ticket all run, in arrival order")
    func unticketedSavesAllRun() async throws {
        let (stack, _) = try makeStack()
        let coordinator = CoreDataSaveCoordinator(stack: stack)
        let log = WorkLog()
        let gate = Gate()

        let a = Task {
            try await coordinator.performSave(operation: "writes") { _ in
                gate.block()
                log.append("a")
            }
        }
        #expect(await waitUntil { gate.isBlocked })
        let b = Task { try await coordinator.performSave(operation: "writes") { _ in log.append("b") } }
        // b has no ticket to observe; give it a moment to queue before c.
        try? await Task.sleep(for: .milliseconds(50))
        let c = Task { try await coordinator.performSave(operation: "writes") { _ in log.append("c") } }
        try? await Task.sleep(for: .milliseconds(50))

        gate.open()
        try await a.value
        try await b.value
        try await c.value

        #expect(log.values.count == 3)
        #expect(log.values.first == "a")
        #expect(Set(log.values) == ["a", "b", "c"])
    }

    // MARK: - Through a repository

    @Test("A burst of account saves leaves the newest snapshot in CoreData")
    func accountSaveBurstLandsTheNewestSnapshot() async throws {
        let (stack, container) = try makeStack()
        let repository = AccountRepository(stack: stack, saveCoordinator: CoreDataSaveCoordinator(stack: stack))

        // Each call adds one account to the previous snapshot, as `addAccount` does.
        var snapshot: [Account] = []
        for index in 0..<20 {
            snapshot.append(Account(id: "acc-\(index)", name: "Account \(index)", currency: "KZT", balance: 0))
            repository.saveAccounts(snapshot)
        }

        let landed = await waitUntil { persistedAccountIds(in: container).count == 20 }
        #expect(landed, "the last snapshot (20 accounts) must reach CoreData; saves were dropped before")
        #expect(Set(persistedAccountIds(in: container)) == Set(snapshot.map(\.id)))
    }
}
