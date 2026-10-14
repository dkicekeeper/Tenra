//
//  AgentThreadStoreTests.swift
//  TenraTests
//
//  The assistant's threads in CoreData (v13, AgentThreadEntity): a thread written comes back
//  whole as the latest, writing it again replaces it, and only the latest `keep` stay.
//

import CoreData
import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct AgentThreadStoreTests {

    private func makeStack() throws -> CoreDataStack {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return CoreDataStack(container: container)
    }

    private func snapshot(_ id: String, at seconds: TimeInterval, question: String = "Сколько на кафе?") -> AgentThreadSnapshot {
        AgentThreadSnapshot(
            id: id,
            createdAt: Date(timeIntervalSince1970: seconds),
            updatedAt: Date(timeIntervalSince1970: seconds),
            title: question,
            body: AgentThreadSnapshot.Body(
                messages: [AgentWireMessage(role: .user, content: [["type": "text", "text": .string(question)]])],
                results: ["r1": ["result_id": "r1", "total": 82_310]],
                owedResults: []
            )
        )
    }

    @Test func aThreadComesBackWhole() async throws {
        let store = AgentThreadStore(stack: try makeStack())
        #expect(await store.latest() == nil)

        let first = snapshot("t1", at: 100)
        await store.save(first)
        #expect(await store.latest() == first)

        // Written again: replaced, not added.
        var later = first
        later.updatedAt = Date(timeIntervalSince1970: 200)
        later.body.owedResults = [["type": "tool_result", "tool_use_id": "toolu_1", "content": "shown"]]
        await store.save(later)
        #expect(await store.latest() == later)
    }

    @Test func onlyTheLatestThreadsStay() async throws {
        let stack = try makeStack()
        let store = AgentThreadStore(stack: stack)
        for index in 0..<(AgentThreadStore.keep + 2) {
            await store.save(snapshot("t\(index)", at: TimeInterval(index)))
        }
        #expect(await store.latest()?.id == "t\(AgentThreadStore.keep + 1)")
        let context = stack.newBackgroundContext()
        let stored = try await context.perform {
            try context.count(for: NSFetchRequest<AgentThreadEntity>(entityName: "AgentThreadEntity"))
        }
        #expect(stored == AgentThreadStore.keep)
    }
}
