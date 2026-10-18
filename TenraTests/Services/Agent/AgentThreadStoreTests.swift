//
//  AgentThreadStoreTests.swift
//  TenraTests
//
//  The assistant's threads in CoreData (v13, AgentThreadEntity): a thread written comes back
//  whole as the latest, writing it again replaces it, only the latest `keep` stay, and the
//  history lists the latest threads with a question and opens one by id.
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

    @Test func theHistoryListsTheLatestThreadsWithAQuestion() async throws {
        let store = AgentThreadStore(stack: try makeStack())
        await store.save(snapshot("old", at: 100, question: "Первый"))
        await store.save(snapshot("mid", at: 200, question: "Второй"))
        await store.save(snapshot("new", at: 300, question: "Третий"))
        var empty = snapshot("empty", at: 400)
        empty.title = nil
        await store.save(empty)

        let recent = await store.recent(limit: 2)
        #expect(recent.map(\.id) == ["new", "mid"])
        #expect(recent.map(\.title) == ["Третий", "Второй"])
        #expect(recent.first?.updatedAt == Date(timeIntervalSince1970: 300))

        #expect(await store.thread(id: "old")?.title == "Первый")
        #expect(await store.thread(id: "missing") == nil)
    }

    @Test func aThreadKeptBeforeFastPathHasNoLocalExchanges() throws {
        let old = Data(#"{"messages":[],"results":{},"owedResults":[]}"#.utf8)
        let body = try JSONDecoder().decode(AgentThreadSnapshot.Body.self, from: old)
        #expect(body.local.isEmpty)

        var kept = body
        kept.local = [AgentThreadSnapshot.LocalExchange(position: 2, question: "кофе 1500", draftId: "draft_3")]
        let again = try JSONDecoder().decode(AgentThreadSnapshot.Body.self, from: JSONEncoder().encode(kept))
        #expect(again == kept)
    }

    @Test func aLongThreadIsKeptCompressedAndAnOldPlainOneStillReads() throws {
        // 60 messages of tool output: far over the ~100 KB at which Core Data would move the
        // value into a file beside the store, which backups don't carry.
        let row = String(repeating: "{\"date\":\"2026-10-01\",\"amount\":1500,\"category\":\"Кафе\"},", count: 60)
        let messages = (0..<60).map { index in
            AgentWireMessage(role: index.isMultiple(of: 2) ? .user : .assistant, content: [["type": "text", "text": .string("\(index) \(row)")]])
        }
        let body = AgentThreadSnapshot.Body(messages: messages, results: ["r1": ["result_id": "r1", "rows": .string(row)]], owedResults: [])
        let json = try JSONEncoder().encode(body)
        #expect(json.count > 200_000)

        let payload = try #require(AgentThreadStore.encodePayload(body))
        #expect(payload.count < 50_000)
        #expect(AgentThreadStore.decodePayload(payload) == body)
        // Threads written before 1.6 (build 27) are plain JSON.
        #expect(AgentThreadStore.decodePayload(json) == body)
        #expect(AgentThreadStore.decodePayload(Data("garbage".utf8)) == nil)
    }
}
