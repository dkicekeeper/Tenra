//
//  AgentConversation.swift
//  Tenra
//
//  Runs the assistant loop for one thread: send the conversation, execute the tools Claude
//  asks for on the phone, send their results, repeat until it calls `render_reply`
//  (docs/plan-ai-assistant.md §3.7). History is append-only: assistant turns are stored as the
//  server returned them and never edited, or the thinking blocks and the prompt cache break.
//

import Foundation

/// Executes one tool on the phone. Implemented by `FinanceToolkit`.
protocol AgentToolExecuting: AnyObject {
    func execute(name: String, input: JSONValue) async -> AgentToolOutput
}

nonisolated struct AgentToolOutput: Sendable, Equatable {
    let value: JSONValue?
    let error: String?

    static func success(_ value: JSONValue) -> AgentToolOutput { AgentToolOutput(value: value, error: nil) }
    static func failure(_ message: String) -> AgentToolOutput { AgentToolOutput(value: nil, error: message) }
}

nonisolated struct AgentTurnOutcome: Sendable, Equatable {
    let reply: AgentReply
    /// Every tool result of the thread by `result_id`; reply blocks read their figures from it.
    let results: [String: JSONValue]
    let model: String
}

nonisolated enum AgentConversationError: Error, Equatable {
    /// The model declined; the turn is dropped and the user can rephrase.
    case refused
    /// A tool call was cut off by the output limit; never run a truncated input.
    case truncated
    /// The turn ended without `render_reply`.
    case noReply
    case invalidReply
    case tooManySteps
    case stream(code: String, retryable: Bool)
}

final class AgentConversation {
    enum Progress: Equatable {
        /// A tool call started on the server side (drives the "thinking" steps).
        case toolStarted(String)
        /// The reply's text blocks so far, while `render_reply` streams (AgentPartialReply).
        case replyText([String])
    }

    private(set) var messages: [AgentWireMessage] = []
    /// Every tool result of the thread by its `result_id`.
    private(set) var results: [String: JSONValue] = [:]
    /// Results owed for the last assistant message (its `render_reply` and any tool called
    /// alongside it). They open the next user message.
    private var owedResults: [JSONValue] = []

    private let transport: AgentTransport
    private let toolkit: AgentToolExecuting
    private let maxSteps: Int

    init(transport: AgentTransport, toolkit: AgentToolExecuting, maxSteps: Int = 8) {
        self.transport = transport
        self.toolkit = toolkit
        self.maxSteps = maxSteps
    }

    /// Starts a new thread: the server keeps nothing, so forgetting the history is all it takes.
    func reset() {
        messages = []
        results = [:]
        owedResults = []
    }

    /// The thread as AgentThreadStore keeps it.
    var body: AgentThreadSnapshot.Body {
        AgentThreadSnapshot.Body(messages: messages, results: results, owedResults: owedResults)
    }

    /// Picks up a kept thread where it stopped.
    func restore(_ body: AgentThreadSnapshot.Body) {
        messages = body.messages
        results = body.results
        owedResults = body.owedResults
    }

    /// The server takes at most 80 messages and one turn adds up to `1 + 2 × maxSteps`, so the
    /// history keeps at most this many before a question.
    static let maxKeptMessages = 60

    /// The server takes a body of at most 256 KB, and one turn's tool results can add half of
    /// that (a year's forecast, a long search), so the history keeps at most this much before
    /// a question.
    static let maxKeptBytes = 128 * 1024

    /// Over `maxKeptMessages` or `maxKeptBytes`, the oldest questions go, whole: the history then
    /// starts at a question, without the results owed to the reply before it. Returns whether
    /// anything went; the <app_context> went with the first message then, so it has to go again.
    @discardableResult
    func trimIfNeeded() -> Bool {
        let encoder = JSONEncoder()
        let sizes = messages.map { (try? encoder.encode($0).count) ?? 0 }
        var earliest = max(0, messages.count - Self.maxKeptMessages)
        var keptBytes = sizes[earliest...].reduce(0, +)
        while keptBytes > Self.maxKeptBytes, earliest < messages.count - 1 {
            keptBytes -= sizes[earliest]
            earliest += 1
        }
        guard earliest > 0 else { return false }
        guard let start = messages.indices.dropFirst(earliest).first(where: { index in
            messages[index].role == .user && messages[index].content.contains { $0["type"] == "text" }
        }) else { return false }
        var kept = Array(messages[start...])
        kept[0] = AgentWireMessage(role: .user, content: kept[0].content.filter { $0["type"] != "tool_result" })
        messages = kept
        return true
    }

    /// Sends one user message and runs the loop to the reply.
    /// - Parameters:
    ///   - context: the `<app_context>` block; pass it on the first message of the thread and
    ///     whenever the date or the user's accounts and categories change.
    ///   - notes: more blocks before the question, each its own text block (an attachment's
    ///     summary), so no block outgrows the server's limit.
    func send(_ text: String, context: String? = nil, notes: [String] = [], onProgress: ((Progress) -> Void)? = nil) async throws -> AgentTurnOutcome {
        let checkpoint = messages.count
        let owed = owedResults
        var content = owedResults
        if let context { content.append(.object(["type": .string("text"), "text": .string(context)])) }
        for note in notes { content.append(.object(["type": .string("text"), "text": .string(note)])) }
        content.append(.object(["type": .string("text"), "text": .string(text)]))
        owedResults = []
        messages.append(AgentWireMessage(role: .user, content: content))
        do {
            return try await run(onProgress: onProgress)
        } catch {
            // Roll the failed turn back so a retry sends a valid history.
            messages.removeSubrange(checkpoint...)
            owedResults = owed
            throw error
        }
    }

    private func run(onProgress: ((Progress) -> Void)?) async throws -> AgentTurnOutcome {
        for _ in 0..<maxSteps {
            var finished: AgentTurnDone?
            // render_reply's input as it streams, in this call only.
            var replyJSON = ""
            var replyTexts: [String] = []
            for try await event in transport.turn(messages) {
                switch event {
                case .tool(let name): onProgress?(.toolStarted(name))
                case .text: break
                case .reply(let piece):
                    replyJSON += piece
                    if let texts = AgentPartialReply.texts(fromPartialJSON: replyJSON), texts != replyTexts {
                        replyTexts = texts
                        onProgress?(.replyText(texts))
                    }
                case .done(let turn): finished = turn
                case .error(let code, let retryable): throw AgentConversationError.stream(code: code, retryable: retryable)
                }
            }
            guard let done = finished else { throw AgentConversationError.noReply }
            if done.refused { throw AgentConversationError.refused }
            if done.truncated { throw AgentConversationError.truncated }

            messages.append(AgentWireMessage(role: .assistant, content: done.content))
            let uses = done.content.compactMap(AgentToolUse.init(block:))
            guard !uses.isEmpty else { throw AgentConversationError.noReply }

            var resultBlocks: [JSONValue] = []
            var reply: AgentReply?
            // render_reply must come alone: next to other calls it can only guess their ids.
            let replyTooEarly = uses.count > 1
            for use in uses {
                if use.name == AgentProtocol.renderReplyTool {
                    if replyTooEarly {
                        resultBlocks.append(AgentToolResult(toolUseId: use.id, content: AgentProtocol.renderReplyTooEarly, isError: true).block)
                        continue
                    }
                    guard let decoded = try? use.input.decoded(as: AgentReply.self) else { throw AgentConversationError.invalidReply }
                    reply = decoded
                    resultBlocks.append(AgentToolResult(toolUseId: use.id, content: "shown", isError: false).block)
                    continue
                }
                let output = await toolkit.execute(name: use.name, input: use.input)
                if let value = output.value {
                    let named = Self.named(value, id: "r\(results.count + 1)")
                    results[named.id] = named.value
                    resultBlocks.append(AgentToolResult(toolUseId: use.id, content: named.value.jsonString(), isError: false).block)
                } else {
                    resultBlocks.append(AgentToolResult(toolUseId: use.id, content: output.error ?? "Tool failed", isError: true).block)
                }
            }

            if let reply {
                owedResults = resultBlocks
                return AgentTurnOutcome(reply: reply, results: results, model: done.model)
            }
            messages.append(AgentWireMessage(role: .user, content: resultBlocks))
        }
        throw AgentConversationError.tooManySteps
    }

    /// The model never sees tool_use ids, so each result carries a short id of its own
    /// (`result_id`: r1, r2, … within the thread) and reply blocks point at that.
    private static func named(_ value: JSONValue, id: String) -> (id: String, value: JSONValue) {
        guard case .object(var fields) = value else {
            return (id, .object([AgentProtocol.resultIdKey: .string(id), "value": value]))
        }
        fields[AgentProtocol.resultIdKey] = .string(id)
        return (id, .object(fields))
    }
}
