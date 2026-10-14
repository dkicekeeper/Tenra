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
    /// Every tool result of the thread by tool_use id; reply blocks read their figures from it.
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
    }

    private(set) var messages: [AgentWireMessage] = []
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

    /// Sends one user message and runs the loop to the reply.
    /// - Parameter context: the `<app_context>` block; pass it on the first message of the
    ///   thread and whenever the date or the user's accounts and categories change.
    func send(_ text: String, context: String? = nil, onProgress: ((Progress) -> Void)? = nil) async throws -> AgentTurnOutcome {
        let checkpoint = messages.count
        let owed = owedResults
        var content = owedResults
        if let context { content.append(.object(["type": .string("text"), "text": .string(context)])) }
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
            for try await event in transport.turn(messages) {
                switch event {
                case .tool(let name): onProgress?(.toolStarted(name))
                case .text: break
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
            for use in uses {
                if use.name == AgentProtocol.renderReplyTool {
                    guard let decoded = try? use.input.decoded(as: AgentReply.self) else { throw AgentConversationError.invalidReply }
                    reply = decoded
                    resultBlocks.append(AgentToolResult(toolUseId: use.id, content: "shown", isError: false).block)
                    continue
                }
                let output = await toolkit.execute(name: use.name, input: use.input)
                if let value = output.value {
                    results[use.id] = value
                    resultBlocks.append(AgentToolResult(toolUseId: use.id, content: value.jsonString(), isError: false).block)
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
}
