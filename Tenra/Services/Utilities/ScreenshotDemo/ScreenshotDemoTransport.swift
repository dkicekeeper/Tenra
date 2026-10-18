//
//  ScreenshotDemoTransport.swift
//  Tenra
//
//  DEBUG-only: Ten's server during screenshot capture. The Simulator has no App Attest and the
//  capture has no network, so a question gets what the model does for "my spending this
//  month": the spending tool, which the real FinanceToolkit answers on the phone from the seeded
//  data, then a reply on cards (the total and the categories) with the lexicon's words. The
//  events come with short pauses, so the chat shows Ten thinking as it does with the server.
//

import Foundation

#if DEBUG

nonisolated final class ScreenshotDemoTransport: AgentTransport, @unchecked Sendable {
    private let reply: ScreenshotDemoReply

    init(reply: ScreenshotDemoReply) {
        self.reply = reply
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let events = Self.events(for: messages, reply: reply)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    try? await Task.sleep(for: .milliseconds(400))
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A message with a question (a text block) asks for the spending; one with only tool
    /// results gets the reply over the result it carries.
    static func events(for messages: [AgentWireMessage], reply: ScreenshotDemoReply) -> [AgentStreamEvent] {
        guard let last = messages.last else { return [] }
        let callId = "demo_\(messages.count)"
        let asks = last.content.contains { $0["type"] == "text" }
        if asks {
            let call = use(id: callId, name: "get_spending_summary", input: [
                "from": .string(reply.from),
                "to": .string(reply.to),
                "type": "expense",
                "group_by": "category",
            ])
            return [.tool(name: "get_spending_summary"), done([call])]
        }
        let source = last.content.lazy.compactMap(resultId(of:)).first ?? "r1"
        let render = use(id: callId, name: AgentProtocol.renderReplyTool, input: [
            "blocks": [
                ["type": "text", "text": .string(reply.text)],
                ["type": "metric", "label": .string(reply.metricLabel), "source": .string(source), "path": "total"],
                ["type": "chart", "kind": "donut", "title": .string(reply.chartTitle), "source": .string(source), "path": "groups"],
            ],
            "mood": "happy",
            "suggestions": .array(reply.suggestions.map(JSONValue.string)),
        ])
        return [.tool(name: AgentProtocol.renderReplyTool), done([render])]
    }

    private static func use(id: String, name: String, input: JSONValue) -> JSONValue {
        ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]
    }

    private static func done(_ content: [JSONValue]) -> AgentStreamEvent {
        .done(AgentTurnDone(
            content: content,
            stopReason: "tool_use",
            model: "screenshot-demo",
            refused: false,
            truncated: false,
            usage: AgentUsage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0),
            tier: "pro",
            quota: nil
        ))
    }

    /// The `result_id` the phone put in a tool result (AgentConversation names them r1, r2…).
    private static func resultId(of block: JSONValue) -> String? {
        guard block["type"] == "tool_result", case .string(let content)? = block["content"],
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(content.utf8)),
              case .string(let id)? = value[AgentProtocol.resultIdKey] else { return nil }
        return id
    }
}

/// What the scripted Ten says, in the app's language: the reply's sentence from the demo
/// lexicon, the card titles and suggestions from the app's own strings.
nonisolated struct ScreenshotDemoReply: Sendable {
    let text: String
    let metricLabel: String
    let chartTitle: String
    let suggestions: [String]
    /// This month so far, as the spending tool takes it.
    let from: String
    let to: String

    @MainActor
    static func current(now: Date = Date(), calendar: Calendar = .current) -> ScreenshotDemoReply {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return ScreenshotDemoReply(
            text: ScreenshotDemoLexicon.current().tenReply,
            metricLabel: String(localized: "insights.expenses"),
            chartTitle: String(localized: "assistant.preset.month"),
            suggestions: [String(localized: "assistant.preset.compare"), String(localized: "assistant.preset.budgets")],
            from: FastDateParser.string(from: start),
            to: FastDateParser.string(from: now)
        )
    }
}

#endif
