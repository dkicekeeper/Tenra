//
//  AgentThreadStore.swift
//  Tenra
//
//  The assistant's threads on the phone (docs/plan-ai-assistant.md §3.4): CoreData v13,
//  `AgentThreadEntity`, the conversation as JSON. The server keeps nothing, so this is the only
//  copy. The latest thread comes back when the assistant opens, a new chat starts another, and
//  only the latest `keep` threads stay; the person can delete one from the assistant's home.
//  Backups carry them with the rest of the store, and "delete all data" removes them with it.
//

import CoreData
import Foundation
import os

/// A thread as kept.
nonisolated struct AgentThreadSnapshot: Equatable, Sendable {
    /// The conversation exactly as sent and received, the tool results its cards read, and the
    /// results owed to the next message (AgentConversation); and the messages the phone
    /// answered by itself, which the model never received (AgentFastPath).
    struct Body: Codable, Equatable, Sendable {
        var messages: [AgentWireMessage]
        var results: [String: JSONValue]
        var owedResults: [JSONValue]
        var local: [LocalExchange]

        init(messages: [AgentWireMessage], results: [String: JSONValue], owedResults: [JSONValue], local: [LocalExchange] = []) {
            self.messages = messages
            self.results = results
            self.owedResults = owedResults
            self.local = local
        }

        private enum CodingKeys: String, CodingKey { case messages, results, owedResults, local }

        /// A thread kept before the phone answered by itself has no `local`.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            messages = try c.decode([AgentWireMessage].self, forKey: .messages)
            results = try c.decode([String: JSONValue].self, forKey: .results)
            owedResults = try c.decode([JSONValue].self, forKey: .owedResults)
            local = try c.decodeIfPresent([LocalExchange].self, forKey: .local) ?? []
        }
    }

    /// A message the phone answered with a draft by itself: where it sits in the thread (the
    /// number of `messages` before it), the message, and the draft it made.
    struct LocalExchange: Codable, Equatable, Sendable {
        var position: Int
        var question: String
        var draftId: String
    }

    var id: String
    var createdAt: Date
    var updatedAt: Date
    /// The first question.
    var title: String?
    var body: Body
}

/// A kept thread in the history list: its first question and when it was last written.
nonisolated struct AgentThreadSummary: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var updatedAt: Date
}

nonisolated final class AgentThreadStore: @unchecked Sendable {
    static let keep = 20

    private static let logger = Logger(subsystem: "Tenra", category: "AgentThreadStore")
    private static let entityName = "AgentThreadEntity"
    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    /// The thread written last; nil when there is none or it cannot be read.
    func latest() async -> AgentThreadSnapshot? {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<AgentThreadEntity>(entityName: Self.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            request.fetchLimit = 1
            return (try? context.fetch(request).first).flatMap(Self.snapshot)
        }
    }

    /// One kept thread, to open it again from the history.
    func thread(id: String) async -> AgentThreadSnapshot? {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<AgentThreadEntity>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            return (try? context.fetch(request).first).flatMap(Self.snapshot)
        }
    }

    /// The latest threads with a question, newest first, without their conversations.
    func recent(limit: Int) async -> [AgentThreadSummary] {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<AgentThreadEntity>(entityName: Self.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            request.predicate = NSPredicate(format: "title != nil AND title != ''")
            request.fetchLimit = limit
            let entities = (try? context.fetch(request)) ?? []
            return entities.compactMap { entity in
                guard let id = entity.id, let title = entity.title else { return nil }
                return AgentThreadSummary(id: id, title: title, updatedAt: entity.updatedAt ?? .distantPast)
            }
        }
    }

    private static func snapshot(_ entity: AgentThreadEntity) -> AgentThreadSnapshot? {
        guard let id = entity.id,
              let payload = entity.payload,
              let body = try? JSONDecoder().decode(AgentThreadSnapshot.Body.self, from: payload) else { return nil }
        return AgentThreadSnapshot(
            id: id,
            createdAt: entity.createdAt ?? .distantPast,
            updatedAt: entity.updatedAt ?? .distantPast,
            title: entity.title,
            body: body
        )
    }

    /// Deletes one kept thread (the person removed it from the assistant's home).
    func delete(id: String) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<AgentThreadEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", id)
                for entity in try context.fetch(request) {
                    context.delete(entity)
                }
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Writes the thread over its earlier copy, and lets the threads beyond `keep` go.
    func save(_ snapshot: AgentThreadSnapshot) async {
        guard let payload = try? JSONEncoder().encode(snapshot.body) else { return }
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<AgentThreadEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", snapshot.id)
                let entity: AgentThreadEntity
                if let existing = try context.fetch(request).first {
                    entity = existing
                } else {
                    // The entity from this context's model: a test host has its own model loaded too.
                    guard let description = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else { return }
                    entity = AgentThreadEntity(entity: description, insertInto: context)
                }
                entity.id = snapshot.id
                entity.createdAt = snapshot.createdAt
                entity.updatedAt = snapshot.updatedAt
                entity.title = snapshot.title
                entity.payload = payload

                let all = NSFetchRequest<AgentThreadEntity>(entityName: Self.entityName)
                all.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
                for old in try context.fetch(all).dropFirst(Self.keep) where old != entity {
                    context.delete(old)
                }
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
