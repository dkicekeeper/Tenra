//
//  AgentTestDoubles.swift
//  TenraTests
//
//  Shared doubles for the assistant tests: a server that plays back scripted turns and records
//  what it was sent, a toolkit with one tool, and builders for the server's content blocks.
//

import Foundation
@testable import Tenra

/// Plays back one scripted response per call and records what was sent.
nonisolated final class ScriptedTransport: AgentTransport, @unchecked Sendable {
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

/// A server that fails before streaming, the way `AgentServerClient` reports HTTP errors.
nonisolated final class FailingTransport: AgentTransport, @unchecked Sendable {
    private let error: Error

    init(_ error: Error) {
        self.error = error
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let error = error
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

final class FakeToolkit: AgentToolExecuting {
    private(set) var executed: [String] = []

    func execute(name: String, input: JSONValue) async -> AgentToolOutput {
        executed.append(name)
        if name == "get_accounts" { return .success(["currency": "KZT", "total_base": 2_334_450]) }
        return .failure("Unknown tool \(name).")
    }
}

enum AgentScript {
    static func done(_ content: [JSONValue], refused: Bool = false, truncated: Bool = false) -> AgentStreamEvent {
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

    static func toolUse(_ id: String, _ name: String, _ input: JSONValue = [:]) -> JSONValue {
        ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]
    }

    static func render(_ id: String, source: String, mood: String = "happy", suggestions: [String] = []) -> JSONValue {
        toolUse(id, "render_reply", [
            "blocks": [
                ["type": "text", "text": "Всего на счетах"],
                ["type": "metric", "label": "Все счета", "source": .string(source), "path": "total_base", "trend_path": nil],
            ],
            "mood": .string(mood),
            "suggestions": .array(suggestions.map(JSONValue.string)),
        ])
    }

    static let thinking: JSONValue = ["type": "thinking", "thinking": "", "signature": "sig"]
}
