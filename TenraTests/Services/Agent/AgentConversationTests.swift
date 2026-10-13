//
//  AgentConversationTests.swift
//  TenraTests
//
//  The assistant loop with a scripted server and a fake toolkit: tools run on the phone,
//  history stays append-only, results owed for `render_reply` open the next message, and a
//  refused, truncated or failed turn leaves no trace.
//

import Foundation
import Testing
@testable import Tenra

/// Plays back one scripted response per call and records what was sent.
private nonisolated final class ScriptedTransport: AgentTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [[AgentStreamEvent]]
    private var sent: [[AgentWireMessage]] = []

    init(_ scripts: [[AgentStreamEvent]]) {
        self.scripts = scripts
    }

    var calls: [[AgentWireMessage]] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        lock.lock()
        sent.append(messages)
        let events = scripts.isEmpty ? [] : scripts.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

private final class FakeToolkit: AgentToolExecuting {
    private(set) var executed: [String] = []

    func execute(name: String, input: JSONValue) async -> AgentToolOutput {
        executed.append(name)
        if name == "get_accounts" { return .success(["currency": "KZT", "total_base": 2_334_450]) }
        return .failure("Unknown tool \(name).")
    }
}

private func done(_ content: [JSONValue], refused: Bool = false, truncated: Bool = false) -> AgentStreamEvent {
    .done(AgentTurnDone(
        content: content,
        stopReason: refused ? "refusal" : "tool_use",
        model: "claude-haiku-5-5",
        refused: refused,
        truncated: truncated,
        usage: AgentUsage(inputTokens: 1, outputTokens: 1, cacheReadInputTokens: 0, cacheCreationInputTokens: 0),
        tier: "pro",
        quota: nil
    ))
}

private func toolUse(_ id: String, _ name: String, _ input: JSONValue = [:]) -> JSONValue {
    ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]
}

private func render(_ id: String, source: String) -> JSONValue {
    toolUse(id, "render_reply", [
        "blocks": [
            ["type": "text", "text": "Всего на счетах"],
            ["type": "metric", "label": "Все счета", "source": .string(source), "path": "total_base", "trend_path": nil],
        ],
        "mood": "happy",
        "suggestions": [],
    ])
}

private let thinking: JSONValue = ["type": "thinking", "thinking": "", "signature": "sig"]

@MainActor
struct AgentConversationTests {

    @Test func runsToolsOnThePhoneAndEndsWithTheReply() async throws {
        let transport = ScriptedTransport([
            [.tool(name: "get_accounts"), done([thinking, toolUse("toolu_1", "get_accounts")])],
            [.tool(name: "render_reply"), done([render("toolu_2", source: "toolu_1")])],
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
        #expect(calls[1][1].content.first == thinking)
        #expect(calls[1][2].content.first?["type"] == "tool_result")
        #expect(calls[1][2].content.first?["tool_use_id"] == "toolu_1")
        #expect(conversation.messages.count == 4)
    }

    @Test func theNextMessageOpensWithTheOwedRenderResult() async throws {
        let transport = ScriptedTransport([
            [done([render("toolu_r", source: "none")])],
            [done([render("toolu_s", source: "none")])],
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
        let conversation = AgentConversation(transport: ScriptedTransport([[done([], refused: true)]]), toolkit: FakeToolkit())
        await #expect(throws: AgentConversationError.refused) {
            _ = try await conversation.send("…")
        }
        #expect(conversation.messages.isEmpty)
    }

    @Test func aTruncatedToolCallIsNeverRun() async {
        let toolkit = FakeToolkit()
        let conversation = AgentConversation(transport: ScriptedTransport([[done([toolUse("toolu_1", "get_accounts")], truncated: true)]]), toolkit: toolkit)
        await #expect(throws: AgentConversationError.truncated) {
            _ = try await conversation.send("…")
        }
        #expect(toolkit.executed.isEmpty)
        #expect(conversation.messages.isEmpty)
    }

    @Test func toolFailuresGoBackAsErrors() async throws {
        let transport = ScriptedTransport([
            [done([toolUse("toolu_1", "delete_everything")])],
            [done([render("toolu_2", source: "toolu_1")])],
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
        let conversation = AgentConversation(transport: ScriptedTransport([[done([["type": "text", "text": "plain"]])]]), toolkit: FakeToolkit())
        await #expect(throws: AgentConversationError.noReply) {
            _ = try await conversation.send("…")
        }
    }
}
