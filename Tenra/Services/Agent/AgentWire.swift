//
//  AgentWire.swift
//  Tenra
//
//  The app ↔ server protocol of the assistant (server/assistant, docs/plan-ai-assistant.md
//  §3.7). One call to `POST /v1/turn` is one model call; the app runs the loop and executes the
//  tools on the phone. Messages use the Anthropic Messages format; content blocks are kept as
//  `JSONValue` so they go back to the server exactly as they came.
//

import Foundation

nonisolated enum AgentProtocol {
    static let version = 1
    /// The terminal tool: every turn ends with one call to it (server/assistant/src/tools.ts).
    static let renderReplyTool = "render_reply"
    /// The error `render_reply` gets when it comes next to other tool calls: their ids do not
    /// exist yet, so its cards could only point at guesses. Mirrored in the server's eval.
    static let renderReplyTooEarly = "render_reply was called together with other tools, before their results existed, so nothing was shown. Call render_reply again, alone, pointing at the results above."
    /// The field that names a tool result; a reply block's `source` is its value.
    static let resultIdKey = "result_id"
}

nonisolated struct AgentWireMessage: Sendable, Equatable, Codable {
    enum Role: String, Sendable, Codable { case user, assistant }

    let role: Role
    let content: [JSONValue]

    static func userText(_ texts: [String]) -> AgentWireMessage {
        AgentWireMessage(role: .user, content: texts.map { .object(["type": .string("text"), "text": .string($0)]) })
    }
}

nonisolated struct AgentTurnRequest: Sendable, Encodable {
    let `protocol`: Int
    let messages: [AgentWireMessage]
    /// The RevenueCat app user id, inside the body App Attest signs: the server looks Pro up
    /// only for this one, never for the `x-tenra-user` header alone.
    let user: String?

    init(messages: [AgentWireMessage], user: String? = nil) {
        self.`protocol` = AgentProtocol.version
        self.messages = messages
        self.user = user
    }
}

/// A tool call Claude asked for, read from an assistant content block.
nonisolated struct AgentToolUse: Sendable, Equatable {
    let id: String
    let name: String
    let input: JSONValue

    init?(block: JSONValue) {
        guard block["type"]?.stringValue == "tool_use",
              let id = block["id"]?.stringValue,
              let name = block["name"]?.stringValue else { return nil }
        self.id = id
        self.name = name
        self.input = block["input"] ?? .object([:])
    }
}

/// A tool result the app sends back in the next user message.
nonisolated struct AgentToolResult: Sendable, Equatable {
    let toolUseId: String
    let content: String
    let isError: Bool

    var block: JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("tool_result"),
            "tool_use_id": .string(toolUseId),
            "content": .string(content),
        ]
        if isError { object["is_error"] = .bool(true) }
        return .object(object)
    }
}

nonisolated struct AgentUsage: Sendable, Equatable, Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

nonisolated struct AgentQuota: Sendable, Equatable, Decodable {
    let used: Int
    let limit: Int
}

/// The `done` event: the assistant turn to append verbatim, plus how it ended.
nonisolated struct AgentTurnDone: Sendable, Equatable, Decodable {
    let content: [JSONValue]
    let stopReason: String?
    let model: String
    let refused: Bool
    let truncated: Bool
    let usage: AgentUsage
    let tier: String?
    let quota: AgentQuota?

    enum CodingKeys: String, CodingKey {
        case content, model, refused, truncated, usage, tier, quota
        case stopReason = "stop_reason"
    }
}

nonisolated enum AgentStreamEvent: Sendable, Equatable {
    /// A tool call started: drives the "thinking" steps in the UI.
    case tool(name: String)
    /// Plain text outside `render_reply`; not shown to the user.
    case text(String)
    /// A piece of `render_reply`'s input JSON as the model writes it (AgentPartialReply).
    case reply(String)
    case done(AgentTurnDone)
    case error(code: String, retryable: Bool)
}

/// Turns the server's SSE lines into events. Feed lines in order, then `finish()`.
/// `URLSession.AsyncBytes.lines` drops blank lines, so an event also completes when the next
/// `event:` line arrives, not only at the blank line that normally ends it.
nonisolated struct AgentSSEParser: Sendable {
    private var event: String?
    private var data: [String] = []

    mutating func feed(line: String) -> AgentStreamEvent? {
        if line.isEmpty { return flush() }
        if line.hasPrefix("event:") {
            let pending = flush()
            event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            return pending
        }
        if line.hasPrefix("data:") {
            data.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    mutating func finish() -> AgentStreamEvent? {
        flush()
    }

    private mutating func flush() -> AgentStreamEvent? {
        defer { event = nil; data = [] }
        guard let event, !data.isEmpty else { return nil }
        return Self.decode(event: event, data: data.joined(separator: "\n"))
    }

    private struct NamePayload: Decodable { let name: String }
    private struct TextPayload: Decodable { let text: String }
    private struct JSONPayload: Decodable { let json: String }
    private struct ErrorPayload: Decodable { let code: String; let retryable: Bool }

    static func decode(event: String, data: String) -> AgentStreamEvent? {
        let bytes = Data(data.utf8)
        let decoder = JSONDecoder()
        switch event {
        case "tool": return (try? decoder.decode(NamePayload.self, from: bytes)).map { .tool(name: $0.name) }
        case "text": return (try? decoder.decode(TextPayload.self, from: bytes)).map { .text($0.text) }
        case "reply": return (try? decoder.decode(JSONPayload.self, from: bytes)).map { .reply($0.json) }
        case "done": return (try? decoder.decode(AgentTurnDone.self, from: bytes)).map { .done($0) }
        case "error":
            let payload = try? decoder.decode(ErrorPayload.self, from: bytes)
            return .error(code: payload?.code ?? "internal", retryable: payload?.retryable ?? false)
        default: return nil
        }
    }
}
