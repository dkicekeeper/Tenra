//
//  AgentConversationTests.swift
//  TenraTests
//
//  The assistant loop with a scripted server and a fake toolkit: tools run on the phone,
//  history stays append-only, results owed for `render_reply` open the next message, a reply
//  sent next to other tools goes back as an error, and a refused, truncated or failed turn
//  leaves no trace.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentConversationTests {

    @Test func runsToolsOnThePhoneAndEndsWithTheReply() async throws {
        let transport = ScriptedTransport([
            [.tool(name: "get_accounts"), AgentScript.done([AgentScript.thinking, AgentScript.toolUse("toolu_1", "get_accounts")])],
            [.tool(name: "render_reply"), AgentScript.done([AgentScript.render("toolu_2", source: "toolu_1")])],
        ])
        let toolkit = FakeToolkit()
        let conversation = AgentConversation(transport: transport, toolkit: toolkit)
        var progress: [AgentConversation.Progress] = []

        let outcome = try await conversation.send("Сколько у меня денег?", context: "<app_context></app_context>") { progress.append($0) }

        #expect(toolkit.executed == ["get_accounts"])
        #expect(progress == [.toolStarted("get_accounts"), .toolStarted("render_reply")])
        #expect(outcome.reply.mood == .happy)
        #expect(outcome.results["toolu_1"]?.value(atPath: "total_base") == .number(2_334_450))
        #expect(outcome.model == "claude-haiku-5-5")

        let calls = transport.calls
        #expect(calls.count == 2)
        // First call: one user message with the context block and the question.
        #expect(calls[0].count == 1)
        #expect(calls[0][0].content.count == 2)
        // Second call: the assistant turn verbatim (thinking kept), then the tool result.
        #expect(calls[1][1].role == .assistant)
        #expect(calls[1][1].content.first == AgentScript.thinking)
        #expect(calls[1][2].content.first?["type"] == "tool_result")
        #expect(calls[1][2].content.first?["tool_use_id"] == "toolu_1")
        #expect(conversation.messages.count == 4)
    }

    @Test func theNextMessageOpensWithTheOwedRenderResult() async throws {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_r", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_s", source: "none")])],
        ])
        let conversation = AgentConversation(transport: transport, toolkit: FakeToolkit())

        _ = try await conversation.send("Привет")
        _ = try await conversation.send("Ещё")

        let latest = try #require(transport.calls.last?.last)
        #expect(latest.role == .user)
        #expect(latest.content.first?["tool_use_id"] == "toolu_r")
        #expect(latest.content.first?["content"] == "shown")
        #expect(latest.content.last?["text"] == "Ещё")
    }

    @Test func aRefusalDropsTheTurn() async {
        let conversation = AgentConversation(transport: ScriptedTransport([[AgentScript.done([], refused: true)]]), toolkit: FakeToolkit())
        await #expect(throws: AgentConversationError.refused) {
            _ = try await conversation.send("…")
        }
        #expect(conversation.messages.isEmpty)
    }

    @Test func aTruncatedToolCallIsNeverRun() async {
        let toolkit = FakeToolkit()
        let conversation = AgentConversation(transport: ScriptedTransport([[AgentScript.done([AgentScript.toolUse("toolu_1", "get_accounts")], truncated: true)]]), toolkit: toolkit)
        await #expect(throws: AgentConversationError.truncated) {
            _ = try await conversation.send("…")
        }
        #expect(toolkit.executed.isEmpty)
        #expect(conversation.messages.isEmpty)
    }

    @Test func aReplyNextToOtherToolsIsSentBack() async throws {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.toolUse("toolu_1", "get_accounts"), AgentScript.render("toolu_2", source: "toolu_guess")])],
            [AgentScript.done([AgentScript.render("toolu_3", source: "toolu_1")])],
        ])
        let toolkit = FakeToolkit()
        let conversation = AgentConversation(transport: transport, toolkit: toolkit)

        let outcome = try await conversation.send("Сколько у меня денег?")

        #expect(toolkit.executed == ["get_accounts"])
        #expect(transport.calls.count == 2)
        let results = transport.calls[1][2].content
        #expect(results.first?["tool_use_id"] == "toolu_1")
        #expect(results.last?["tool_use_id"] == "toolu_2")
        #expect(results.last?["is_error"] == .bool(true))
        #expect(outcome.reply.blocks.last?.source == "toolu_1")
    }

    @Test func toolFailuresGoBackAsErrors() async throws {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.toolUse("toolu_1", "delete_everything")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "toolu_1")])],
        ])
        let conversation = AgentConversation(transport: transport, toolkit: FakeToolkit())

        let outcome = try await conversation.send("…")

        #expect(outcome.results["toolu_1"] == nil)
        let result = try #require(transport.calls[1][2].content.first)
        #expect(result["is_error"] == .bool(true))
    }

    @Test func streamErrorsRollTheTurnBack() async {
        let conversation = AgentConversation(transport: ScriptedTransport([[.error(code: "upstream_busy", retryable: true)]]), toolkit: FakeToolkit())
        await #expect(throws: AgentConversationError.stream(code: "upstream_busy", retryable: true)) {
            _ = try await conversation.send("…")
        }
        #expect(conversation.messages.isEmpty)
    }

    @Test func aTurnWithoutRenderReplyIsAnError() async {
        let conversation = AgentConversation(transport: ScriptedTransport([[AgentScript.done([["type": "text", "text": "plain"]])]]), toolkit: FakeToolkit())
        await #expect(throws: AgentConversationError.noReply) {
            _ = try await conversation.send("…")
        }
    }
}
