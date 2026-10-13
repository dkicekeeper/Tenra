//
//  AssistantViewModelTests.swift
//  TenraTests
//
//  The assistant screen's state over a scripted server: the thread of questions and replies,
//  the step named after the running tool, a failed question kept for Retry, and the
//  <app_context> block sent only when it changed.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantViewModelTests {

    private func makeModel(_ transport: AgentTransport, context: @escaping () -> String = { "<app_context>a</app_context>" }) -> AssistantViewModel {
        AssistantViewModel(conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()), context: context)
    }

    @Test func aQuestionAndItsReplyJoinTheThread() async {
        let transport = ScriptedTransport([
            [.tool(name: "get_accounts"), AgentScript.done([AgentScript.toolUse("toolu_1", "get_accounts")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "toolu_1", mood: "celebrate", suggestions: ["Ещё"])])],
        ])
        let model = makeModel(transport)

        await model.send("  Сколько у меня денег?  ")

        #expect(model.phase == .idle)
        #expect(model.entries.count == 2)
        #expect(model.entries.first?.content == .question("Сколько у меня денег?"))
        guard case .reply(let reply, let results)? = model.entries.last?.content else {
            Issue.record("expected a reply")
            return
        }
        #expect(reply.mood == .celebrate)
        #expect(results["toolu_1"]?["total_base"] == .number(2_334_450))
        #expect(model.replyMood == .celebrate)
        #expect(model.suggestions == ["Ещё"])
    }

    @Test func blankQuestionsAreIgnored() async {
        let transport = ScriptedTransport([])
        let model = makeModel(transport)
        await model.send("   ")
        #expect(model.entries.isEmpty)
        #expect(transport.calls.isEmpty)
    }

    @Test func theContextGoesOnlyWhenItChanged() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_3", source: "none")])],
        ])
        var context = "<app_context>day 1</app_context>"
        let model = makeModel(transport, context: { context })

        await model.send("Первый")
        await model.send("Второй")
        context = "<app_context>day 2</app_context>"
        await model.send("Третий")

        let firsts = transport.calls.map { call in call.last?.content.compactMap { $0["text"]?.stringValue } ?? [] }
        #expect(firsts[0] == ["<app_context>day 1</app_context>", "Первый"])
        #expect(firsts[1] == ["Второй"])
        #expect(firsts[2] == ["<app_context>day 2</app_context>", "Третий"])
    }

    @Test func aFailedQuestionStaysForRetry() async {
        let transport = ScriptedTransport([
            [.error(code: "upstream_busy", retryable: true)],
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
        ])
        let model = makeModel(transport)

        await model.send("Сколько на кафе?")
        #expect(model.phase == .failed(.busy))
        #expect(model.entries.count == 1)
        #expect(model.failedEntry == model.entries.first?.id)
        #expect(model.suggestions.isEmpty)

        await model.retry()
        #expect(model.phase == .idle)
        #expect(model.entries.count == 2)
        #expect(model.failedEntry == nil)
        // The retry sends the same question again, with the context it never delivered.
        let retried = transport.calls[1].last?.content.compactMap { $0["text"]?.stringValue }
        #expect(retried == ["<app_context>a</app_context>", "Сколько на кафе?"])
    }

    @Test func movingOnDropsTheFailedQuestion() async {
        let transport = ScriptedTransport([
            [.error(code: "internal", retryable: false)],
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
        ])
        let model = makeModel(transport)

        await model.send("Первый")
        #expect(model.phase == .failed(.generic))
        await model.send("Второй")

        #expect(model.entries.count == 2)
        #expect(model.entries.first?.content == .question("Второй"))
    }

    @Test func serverErrorsBecomeWordsForThePerson() async {
        let limit = makeModel(FailingTransport(AgentServerError.quotaExceeded(limit: 900)))
        await limit.send("…")
        #expect(limit.phase == .failed(.limitReached))
        #expect(AssistantFailure.limitReached.canRetry == false)

        let offline = makeModel(FailingTransport(URLError(.notConnectedToInternet)))
        await offline.send("…")
        #expect(offline.phase == .failed(.offline))
        #expect(AssistantFailure.offline.canRetry)

        #expect(AssistantFailure(AgentServerError.unauthorized) == .proRequired)
        #expect(AssistantFailure(AgentServerError.regionUnavailable) == .regionUnavailable)
        #expect(AssistantFailure(AgentConversationError.refused) == .refused)
    }

    @Test func stepsAreNamedAfterTheTools() {
        #expect(AssistantStep(tool: "get_spending_summary") == .spending)
        #expect(AssistantStep(tool: "render_reply") == .composing)
        #expect(AssistantStep(tool: "something_new") == .understanding)
    }
}
