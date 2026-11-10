//
//  AssistantRegionTests.swift
//  TenraTests
//
//  Where the cloud does not answer (the server's 451 for Russia and Belarus): Ten says so once,
//  as its own message rather than an error, sends no more questions for a week and keeps
//  recording expenses on the phone; a week on, one question goes to the server again
//  (docs/domains/assistant.md §10). Each test keeps the state in its own UserDefaults suite.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantRegionTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A server for a country the cloud does not serve: 451 on every turn, counted.
    nonisolated final class RefusingTransport: AgentTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
            lock.lock()
            count += 1
            lock.unlock()
            return AsyncThrowingStream { $0.finish(throwing: AgentServerError.regionUnavailable) }
        }
    }

    private func makeRegion() -> AssistantRegion {
        AssistantRegion(defaults: UserDefaults(suiteName: "AssistantRegionTests.\(UUID().uuidString)")!)
    }

    private func makeModel(_ transport: AgentTransport, region: AssistantRegion) -> AssistantViewModel {
        var access = AssistantViewModel.Access.unlimited
        access.region = region
        access.now = { Self.now }
        return AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            access: access
        )
    }

    @Test("Out of the region for a week after a refusal, then asked again")
    func weekRule() {
        #expect(!AssistantRegion.isOutOfRegion(markedAt: 0, now: Self.now))
        let marked = Self.now.timeIntervalSince1970
        #expect(AssistantRegion.isOutOfRegion(markedAt: marked, now: Self.now.addingTimeInterval(6 * 86_400)))
        #expect(!AssistantRegion.isOutOfRegion(markedAt: marked, now: Self.now.addingTimeInterval(7 * 86_400)))
    }

    @Test("Explained once ever; an answer clears the mark, not the explanation")
    func marks() {
        let region = makeRegion()
        #expect(region.markOutOfRegion(now: Self.now))
        #expect(region.isOutOfRegion(now: Self.now))
        #expect(!region.markOutOfRegion(now: Self.now))
        region.markServed()
        #expect(!region.isOutOfRegion(now: Self.now))
        #expect(!region.markOutOfRegion(now: Self.now))
    }

    @Test("The first refusal is Ten's message; the next question does not go out")
    func explainsOnceThenStaysOnThePhone() async {
        let transport = RefusingTransport()
        let model = makeModel(transport, region: makeRegion())

        await model.send("Сколько я потратил на кафе?")
        #expect(model.phase == .idle)
        #expect(model.entries.count == 2)
        #expect(model.entries.first?.content == .question("Сколько я потратил на кафе?"))
        #expect(model.entries.last?.content == .reply(AssistantViewModel.regionReply, results: [:]))
        #expect(model.suggestions.isEmpty)
        #expect(transport.calls == 1)

        await model.send("А на такси?")
        #expect(model.phase == .failed(.regionUnavailable))
        #expect(transport.calls == 1)
    }

    @Test("A week on a question goes out again; refused again, the short answer")
    func askedAgainAfterAWeek() async {
        let region = makeRegion()
        region.markOutOfRegion(now: Self.now.addingTimeInterval(-8 * 86_400))
        let transport = RefusingTransport()
        let model = makeModel(transport, region: region)

        await model.send("Сколько я потратил?")
        #expect(transport.calls == 1)
        #expect(model.phase == .failed(.regionUnavailable))
        #expect(region.isOutOfRegion(now: Self.now))
    }
}
