//
//  AgentMemory.swift
//  Tenra
//
//  What Ten remembers about the person across chats (docs/domains/assistant.md §5): short
//  facts about their money ("salary comes on the 10th", "saving for a car", "Kaspi is the main
//  card"). The model proposes one with `draft_fact` and the person keeps it with Save on the
//  card, like any draft (AgentDraftBook); Settings → Assistant → "What Ten knows about me"
//  (AssistantMemoryView) lists them to add, edit or forget. The facts go to the model in
//  `<app_context>` (AgentContextBuilder), so every chat starts knowing them.
//
//  Kept in CoreData v14 (`AgentFactEntity`, AgentFactStore), outside the repository facade like
//  the threads: backups carry them, "delete all data" removes them, and the list reloads when
//  the store is replaced.
//

import CoreData
import Foundation
import Observation
import os

/// One remembered fact. Its id is short ("f3"), for the model to name it.
nonisolated struct AgentFact: Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
}

/// A fact to remember, change or forget, as the card shows it before Save.
struct AgentFactDraft: Equatable {
    /// The new text; nil forgets `replaces`.
    var text: String?
    /// The fact it changes or forgets, as it was when drafted.
    var replaces: AgentFact?
}

/// What saving a fact draft changed, for Undo.
struct AgentFactChange: Equatable {
    var before: AgentFact?
    var after: AgentFact?
}

nonisolated enum AgentMemoryError: Error, Equatable {
    case empty
    case tooLong
    case full
    /// The same text is remembered already, under this id.
    case duplicate(String)
    /// The fact to change or forget is gone.
    case unknown(String)
}

// MARK: - Store

nonisolated final class AgentFactStore: @unchecked Sendable {
    private static let logger = Logger(subsystem: "Tenra", category: "AgentFactStore")
    private static let entityName = "AgentFactEntity"
    let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    /// Every fact, oldest first.
    func all() async -> [AgentFact] {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<AgentFactEntity>(entityName: Self.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let entities = (try? context.fetch(request)) ?? []
            return entities.compactMap { entity in
                guard let id = entity.id, !id.isEmpty, let text = entity.text, !text.isEmpty else { return nil }
                return AgentFact(id: id, text: text, createdAt: entity.createdAt ?? .distantPast, updatedAt: entity.updatedAt ?? .distantPast)
            }
        }
    }

    /// Writes the fact over its earlier copy, or adds it.
    func save(_ fact: AgentFact) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<AgentFactEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", fact.id)
                let entity: AgentFactEntity
                if let existing = try context.fetch(request).first {
                    entity = existing
                } else {
                    // The entity from this context's model: a test host has its own model loaded too.
                    guard let description = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else { return }
                    entity = AgentFactEntity(entity: description, insertInto: context)
                }
                entity.id = fact.id
                entity.text = fact.text
                entity.createdAt = fact.createdAt
                entity.updatedAt = fact.updatedAt
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Deletes the facts with these ids; none deletes them all.
    func delete(ids: [String]? = nil) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<AgentFactEntity>(entityName: Self.entityName)
                if let ids { request.predicate = NSPredicate(format: "id IN %@", ids) }
                for entity in try context.fetch(request) {
                    context.delete(entity)
                }
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Memory

@Observable
final class AgentMemory {
    static let shared = AgentMemory(store: AgentFactStore())

    /// Facts kept at most: the context stays short.
    static let limit = 30
    /// Characters in one fact at most.
    static let maxLength = 200

    /// Oldest first.
    private(set) var facts: [AgentFact] = []
    /// The kept facts have been read: an empty list means there are none.
    private(set) var isLoaded: Bool

    @ObservationIgnored private let store: AgentFactStore?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// The highest id number given out, so a forgotten fact's id is not given to a new one in
    /// the same run (a thread may still name it).
    @ObservationIgnored private var lastNumber = 0
    @ObservationIgnored private var resetObserver: NSObjectProtocol?

    /// - Parameter store: nil keeps the facts in memory only (previews, tests).
    init(store: AgentFactStore?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        self.isLoaded = store == nil
        if let stack = store?.stack {
            // "Delete all data" and a restored backup replace the store: read it again.
            resetObserver = NotificationCenter.default.addObserver(
                forName: CoreDataStack.storeDidResetNotification,
                object: stack,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = nil
                    Task { await self.load() }
                }
            }
        }
    }

    /// Reads the kept facts, once; later calls wait for that read.
    func load() async {
        if let loading { return await loading.value }
        guard let store else { return }
        let task = Task { @MainActor in
            let kept = await store.all()
            self.facts = kept
            self.isLoaded = true
            self.lastNumber = max(self.lastNumber, kept.compactMap { Self.number($0.id) }.max() ?? 0)
        }
        loading = task
        await task.value
    }

    /// The text as it is kept: one line, trimmed. Throws when it is empty or too long.
    static func normalized(_ text: String) throws -> String {
        let line = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !line.isEmpty else { throw AgentMemoryError.empty }
        guard line.count <= maxLength else { throw AgentMemoryError.tooLong }
        return line
    }

    /// Checks a draft against the facts now: the text is valid, the fact it replaces exists, a
    /// new fact fits and is not remembered already. Returns the draft with its text normalized
    /// and the replaced fact as it is now.
    func validated(text: String?, replacing id: String?) throws -> AgentFactDraft {
        let replaced: AgentFact?
        if let id {
            guard let fact = facts.first(where: { $0.id == id }) else { throw AgentMemoryError.unknown(id) }
            replaced = fact
        } else {
            replaced = nil
        }
        guard let text else {
            guard replaced != nil else { throw AgentMemoryError.empty }
            return AgentFactDraft(text: nil, replaces: replaced)
        }
        let line = try Self.normalized(text)
        if let same = facts.first(where: { $0.text.lowercased() == line.lowercased() && $0.id != id }) {
            throw AgentMemoryError.duplicate(same.id)
        }
        if replaced == nil, facts.count >= Self.limit { throw AgentMemoryError.full }
        return AgentFactDraft(text: line, replaces: replaced)
    }

    /// Remembers a new fact.
    @discardableResult
    func remember(_ text: String) async throws -> AgentFact {
        guard let fact = try await apply(AgentFactDraft(text: text, replaces: nil)).after else { throw AgentMemoryError.empty }
        return fact
    }

    /// Changes a fact's text.
    func change(_ id: String, to text: String) async throws {
        guard let fact = facts.first(where: { $0.id == id }) else { throw AgentMemoryError.unknown(id) }
        try await apply(AgentFactDraft(text: text, replaces: fact))
    }

    func forget(_ id: String) async {
        _ = try? await apply(AgentFactDraft(text: nil, replaces: facts.first { $0.id == id }))
    }

    func forgetAll() async {
        facts = []
        await store?.delete()
    }

    /// Saves a draft (the card's Save, the settings screen): checked again against the facts now.
    @discardableResult
    func apply(_ draft: AgentFactDraft) async throws -> AgentFactChange {
        await load()
        let checked = try validated(text: draft.text, replacing: draft.replaces?.id)
        let date = now()
        switch (checked.text, checked.replaces) {
        case (let text?, let before?):
            var after = before
            after.text = text
            after.updatedAt = date
            put(after)
            await store?.save(after)
            return AgentFactChange(before: before, after: after)
        case (let text?, nil):
            lastNumber += 1
            let fact = AgentFact(id: "f\(lastNumber)", text: text, createdAt: date, updatedAt: date)
            put(fact)
            await store?.save(fact)
            return AgentFactChange(before: nil, after: fact)
        case (nil, let before?):
            facts.removeAll { $0.id == before.id }
            await store?.delete(ids: [before.id])
            return AgentFactChange(before: before, after: nil)
        case (nil, nil):
            throw AgentMemoryError.empty
        }
    }

    /// Takes a saved change back: a new fact goes, a changed or forgotten one returns as it was.
    func revert(_ change: AgentFactChange) async {
        await load()
        if let before = change.before {
            put(before)
            await store?.save(before)
        } else if let after = change.after {
            facts.removeAll { $0.id == after.id }
            await store?.delete(ids: [after.id])
        }
    }

    /// Puts the fact in its place by when it was made.
    private func put(_ fact: AgentFact) {
        facts.removeAll { $0.id == fact.id }
        let index = facts.firstIndex { $0.createdAt > fact.createdAt } ?? facts.endIndex
        facts.insert(fact, at: index)
        lastNumber = max(lastNumber, Self.number(fact.id) ?? 0)
    }

    private static func number(_ id: String) -> Int? {
        guard id.hasPrefix("f") else { return nil }
        return Int(id.dropFirst())
    }
}
