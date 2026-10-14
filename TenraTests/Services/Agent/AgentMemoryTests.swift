//
//  AgentMemoryTests.swift
//  TenraTests
//
//  What the assistant remembers (AgentMemory, CoreData v14 AgentFactEntity): a fact is one
//  trimmed line under the limit, gets a short id that is not given out again in the same run,
//  is not remembered twice, changes and goes, and Undo puts it back. `draft_fact` checks a draft
//  against the facts now and files it; saving it through the book writes it to memory. The
//  store keeps the facts across a new memory over the same stack, numbering on from them.
//

import CoreData
import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct AgentMemoryTests {

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

    @Test func aFactIsOneShortLine() throws {
        #expect(try AgentMemory.normalized("  Зарплата\n приходит 10-го  ") == "Зарплата приходит 10-го")
        #expect(throws: AgentMemoryError.empty) { try AgentMemory.normalized(" \n ") }
        #expect(throws: AgentMemoryError.tooLong) { try AgentMemory.normalized(String(repeating: "а", count: AgentMemory.maxLength + 1)) }
        #expect(try AgentMemory.normalized(String(repeating: "а", count: AgentMemory.maxLength)).count == AgentMemory.maxLength)
    }

    @Test func factsAreRememberedChangedAndForgotten() async throws {
        let memory = AgentMemory(store: nil)
        let salary = try await memory.remember("Зарплата приходит 10-го")
        let car = try await memory.remember("Копит на машину")
        #expect(salary.id == "f1")
        #expect(car.id == "f2")

        // Not twice, whatever the case.
        await #expect(throws: AgentMemoryError.duplicate("f1")) { try await memory.remember("зарплата приходит 10-го") }

        try await memory.change("f1", to: "Зарплата приходит 15-го")
        #expect(memory.facts.map(\.text) == ["Зарплата приходит 15-го", "Копит на машину"])
        await #expect(throws: AgentMemoryError.unknown("f9")) { try await memory.change("f9", to: "Что-то") }

        await memory.forget("f2")
        #expect(memory.facts.map(\.id) == ["f1"])
        // A forgotten id is not given to a new fact in the same run: a thread may still name it.
        #expect(try await memory.remember("Основная карта Kaspi").id == "f3")

        await memory.forgetAll()
        #expect(memory.facts.isEmpty)
    }

    @Test func undoPutsTheFactBack() async throws {
        let memory = AgentMemory(store: nil)
        let fact = try await memory.remember("Копит на машину")

        let changed = try await memory.apply(AgentFactDraft(text: "Копит на квартиру", replaces: fact))
        await memory.revert(changed)
        #expect(memory.facts.map(\.text) == ["Копит на машину"])

        let forgotten = try await memory.apply(AgentFactDraft(text: nil, replaces: fact))
        #expect(memory.facts.isEmpty)
        await memory.revert(forgotten)
        #expect(memory.facts == [fact])

        let added = try await memory.apply(AgentFactDraft(text: "Долг другу до декабря", replaces: nil))
        await memory.revert(added)
        #expect(memory.facts == [fact])
    }

    @Test func theMemoryHasALimit() async throws {
        let memory = AgentMemory(store: nil)
        for index in 0..<AgentMemory.limit {
            try await memory.remember("Факт номер \(index)")
        }
        await #expect(throws: AgentMemoryError.full) { try await memory.remember("Ещё один") }
        // A change still fits.
        try await memory.change("f1", to: "Факт номер один")
        #expect(memory.facts.count == AgentMemory.limit)
    }

    @Test func theStoreKeepsFactsAcrossLaunches() async throws {
        let stack = try makeStack()
        let first = AgentMemory(store: AgentFactStore(stack: stack))
        await first.load()
        #expect(first.isLoaded)
        #expect(first.facts.isEmpty)
        try await first.remember("Зарплата приходит 10-го")
        try await first.remember("Копит на машину")
        try await first.change("f1", to: "Зарплата приходит 15-го")
        await first.forget("f2")
        try await first.remember("Основная карта Kaspi")

        let second = AgentMemory(store: AgentFactStore(stack: stack))
        #expect(!second.isLoaded)
        await second.load()
        #expect(second.facts.map(\.id) == ["f1", "f3"])
        #expect(second.facts.map(\.text) == ["Зарплата приходит 15-го", "Основная карта Kaspi"])
        // Numbering goes on from the kept facts.
        #expect(try await second.remember("Долг другу до декабря").id == "f4")

        await second.forgetAll()
        #expect(await AgentFactStore(stack: stack).all().isEmpty)
    }

    // MARK: - draft_fact

    private static func make(memory: AgentMemory) -> (FinanceToolkit, AgentDraftBook, TransactionStore) {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { operation in
                guard case .fact(let fact) = operation else { throw FinanceToolError(message: "unexpected") }
                return .fact(try await memory.apply(fact))
            },
            undo: { record in
                if case .fact(let change) = record { await memory.revert(change) }
            }
        ))
        let toolkit = FinanceToolkit(store: store, drafts: book, memory: memory, learned: VoiceLearningStore(defaults: defaults))
        return (toolkit, book, store)
    }

    @Test func draftFactFilesADraftThatSaveRemembers() async throws {
        let memory = AgentMemory(store: nil)
        let (toolkit, book, store) = Self.make(memory: memory)
        _ = store

        let output = await toolkit.execute(name: "draft_fact", input: ["text": "  Копит на отпуск к июлю ", "replaces": .null])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["draft_id"] == "draft_1")
        #expect(result["action"] == "remember")
        #expect(result["text"] == "Копит на отпуск к июлю")
        // Nothing is remembered before Save.
        #expect(memory.facts.isEmpty)

        await book.save("draft_1")
        #expect(memory.facts.map(\.text) == ["Копит на отпуск к июлю"])
        await book.undo("draft_1")
        #expect(memory.facts.isEmpty)
    }

    @Test func draftFactChangesAndForgetsByIdAndRefusesWhatItCannot() async throws {
        let memory = AgentMemory(store: nil)
        try await memory.remember("Зарплата приходит 10-го")
        let (toolkit, book, store) = Self.make(memory: memory)
        _ = store

        let change = await toolkit.execute(name: "draft_fact", input: ["text": "Зарплата приходит 15-го", "replaces": "f1"])
        let changed = try #require(change.value, "\(change.error ?? "")")
        #expect(changed["action"] == "change")
        #expect(changed["previous_text"] == "Зарплата приходит 10-го")
        let operation = try #require(book.drafts["draft_1"]?.operations.first)
        #expect(toolkit.describe(operation) == ["type": "fact", "text": "Зарплата приходит 15-го", "replaces": "f1"])

        let forget = await toolkit.execute(name: "draft_fact", input: ["text": .null, "replaces": "f1"])
        let forgotten = try #require(forget.value, "\(forget.error ?? "")")
        #expect(forgotten["action"] == "forget")
        #expect(forgotten["text"] == .null)

        for (input, label) in [
            (["text": "Что-то", "replaces": "f9"] as JSONValue, "unknown id"),
            (["text": .null, "replaces": .null] as JSONValue, "nothing to forget"),
            (["text": "зарплата приходит 10-го", "replaces": .null] as JSONValue, "remembered already"),
        ] {
            let output = await toolkit.execute(name: "draft_fact", input: input)
            #expect(output.error != nil, "\(label) should be refused")
        }
        #expect(book.drafts.count == 2)
    }
}
