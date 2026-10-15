//
//  ScreenshotDemoTransport.swift
//  Tenra
//
//  DEBUG-only: Ten's server in screenshot capture (ScreenshotDemoMode), with no network. It
//  plays the turns a model would (docs/plan-ai-assistant.md §3.7): tool calls first, which the
//  app runs on the phone like any (FinanceToolkit over the seeded data, so every figure on the
//  cards is real), then `render_reply` alone, pointing at the results by their `result_id`.
//  Only the reply's words are scripted, per language (ScreenshotDemoLexicon.ten()).
//
//  "My spending this month" (the first ready-made question on Ten's home) gets this month so
//  far against the same days of last month and a breakdown by category. Anything else is
//  drafted as a coffee: the voice sheet's phrase is a plain record the phone drafts itself
//  (AgentFastPath), so this only answers when the parser does not take it.
//

import Foundation

#if DEBUG

nonisolated struct ScreenshotDemoTransport: AgentTransport {

    /// The words and the draft, captured on the main actor where the lexicon lives.
    nonisolated struct Script: Sendable {
        let monthQuestion: String
        let intro: String
        let metricLabel: String
        let chartTitle: String
        let tip: String
        let suggestions: [String]
        let draftNote: String
        let draftAmount: Double
        let draftCategory: String
    }

    let script: Script
    /// The pause before each event, so Ten thinks the way it does with a server.
    let beat: Duration

    init(script: Script, beat: Duration = .zero) {
        self.script = script
        self.beat = beat
    }

    /// The script in the app's language and the demo currency.
    @MainActor
    init() {
        let lexicon = ScreenshotDemoLexicon.current()
        let ten = ScreenshotDemoLexicon.ten()
        let dining = CategoryPreset.defaultExpense.first { $0.id == "dining" }
        beat = .milliseconds(400)
        script = Script(
            monthQuestion: String(localized: "assistant.preset.month"),
            intro: ten.answerIntro,
            metricLabel: ten.answerMetric,
            chartTitle: ten.answerChart,
            tip: ten.answerTip,
            suggestions: [
                String(localized: "assistant.preset.budgets"),
                String(localized: "assistant.preset.save"),
            ],
            draftNote: lexicon.coffee,
            draftAmount: ScreenshotDemoCurrency.amount(4.5, in: ScreenshotDemoMode.currencyCode),
            draftCategory: dining.map { String(localized: String.LocalizationValue($0.nameKey)) } ?? lexicon.coffee
        )
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let events = Self.events(for: messages, script: script)
        let beat = beat
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    if beat > .zero { try? await Task.sleep(for: beat) }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Turns

    private nonisolated enum Call {
        static let compare = "demo_compare"
        static let summary = "demo_summary"
        static let draft = "demo_draft"
        static let reply = "demo_reply"
    }

    static func events(for messages: [AgentWireMessage], script: Script) -> [AgentStreamEvent] {
        guard let last = messages.last, last.role == .user else { return [.error(code: "invalid", retryable: false)] }
        // A question ends with its text; the results of the tools come back without one.
        if let question = last.content.last(where: { $0["type"] == "text" })?["text"]?.stringValue {
            return firstStep(for: question, script: script)
        }
        return reply(to: results(in: last), script: script)
    }

    /// The tools a model would call for the question.
    private static func firstStep(for question: String, script: Script) -> [AgentStreamEvent] {
        let asksForMonth = question == script.monthQuestion || !question.contains(where: \.isNumber)
        guard asksForMonth else {
            let item: JSONValue = [
                "type": "expense",
                "amount": .number(script.draftAmount),
                "currency": nil,
                "category": .string(script.draftCategory),
                "account": nil,
                "to_account": nil,
                "date": nil,
                "note": .string(script.draftNote),
            ]
            return [
                .tool(name: "draft_transactions"),
                done([toolUse(Call.draft, "draft_transactions", ["items": [item]])]),
            ]
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let previousSameDay = calendar.date(byAdding: .month, value: -1, to: today) ?? previousStart
        let from = JSONValue.string(FastDateParser.string(from: monthStart))
        let to = JSONValue.string(FastDateParser.string(from: today))
        let previous: JSONValue = [
            "from": .string(FastDateParser.string(from: previousStart)),
            "to": .string(FastDateParser.string(from: previousSameDay)),
        ]
        return [
            .tool(name: "compare_periods"),
            .tool(name: "get_spending_summary"),
            done([
                toolUse(Call.compare, "compare_periods", [
                    "type": "expense",
                    "current": ["from": from, "to": to],
                    "previous": previous,
                    "group_by": "none",
                ]),
                toolUse(Call.summary, "get_spending_summary", ["from": from, "to": to, "type": "expense", "group_by": "category"]),
            ]),
        ]
    }

    /// The tool results the phone sent back, by the call they answer.
    private static func results(in message: AgentWireMessage) -> [String: JSONValue] {
        var found: [String: JSONValue] = [:]
        for block in message.content where block["type"] == "tool_result" && block["is_error"]?.boolValue != true {
            guard let id = block["tool_use_id"]?.stringValue,
                  let content = block["content"]?.stringValue,
                  let value = try? JSONDecoder().decode(JSONValue.self, from: Data(content.utf8)) else { continue }
            found[id] = value
        }
        return found
    }

    /// `render_reply`, alone, over the results.
    private static func reply(to results: [String: JSONValue], script: Script) -> [AgentStreamEvent] {
        let resultId: (String) -> JSONValue? = { results[$0]?[AgentProtocol.resultIdKey] }
        var blocks: [JSONValue] = []
        var mood = "happy"
        var suggestions: [String] = []
        if let draftId = results[Call.draft]?["draft_id"] {
            blocks = [["type": "confirm", "draft_id": draftId]]
        } else {
            blocks.append(["type": "text", "text": .string(script.intro)])
            if let compare = resultId(Call.compare) {
                blocks.append([
                    "type": "metric",
                    "label": .string(script.metricLabel),
                    "source": compare,
                    "path": "current.total",
                    "trend_path": "change_percent",
                ])
            }
            if let summary = resultId(Call.summary) {
                blocks.append(["type": "chart", "kind": "donut", "title": .string(script.chartTitle), "source": summary, "path": "groups"])
            }
            blocks.append(["type": "text", "text": .string(script.tip)])
            suggestions = script.suggestions
            if blocks.count == 2 { mood = "idle" }
        }
        let input: JSONValue = [
            "blocks": .array(blocks),
            "mood": .string(mood),
            "suggestions": .array(suggestions.map(JSONValue.string)),
        ]
        return [
            .tool(name: AgentProtocol.renderReplyTool),
            .reply(input.jsonString()),
            done([toolUse(Call.reply, AgentProtocol.renderReplyTool, input)]),
        ]
    }

    // MARK: - Blocks

    private static func toolUse(_ id: String, _ name: String, _ input: JSONValue) -> JSONValue {
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
}

#endif
