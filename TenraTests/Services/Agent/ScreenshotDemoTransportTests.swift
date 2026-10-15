//
//  ScreenshotDemoTransportTests.swift
//  TenraTests
//
//  Ten's scripted server for screenshot capture (DEBUG): its turns run through the real loop
//  (AgentConversation), so the protocol it plays is the one the app checks. The month question
//  gets its two read tools and a reply whose cards point at their results; anything else is
//  drafted and answered with the draft's card. Each question starts over with the owed result.
//

#if DEBUG

import Foundation
import Testing
@testable import Tenra

@MainActor
struct ScreenshotDemoTransportTests {

    private let script = ScreenshotDemoTransport.Script(
        monthQuestion: "My spending this month",
        intro: "**Here's your month so far.**",
        metricLabel: "Spent this month",
        chartTitle: "By category",
        tip: "Groceries change the most.",
        suggestions: ["How are my budgets?"],
        draftNote: "Coffee",
        draftAmount: 4.5,
        draftCategory: "Eating out"
    )

    /// Answers the read tools with figures of the toolkit's shapes and drafts with an id.
    private final class DemoToolkit: AgentToolExecuting {
        private(set) var executed: [String] = []
        private(set) var inputs: [String: JSONValue] = [:]

        func execute(name: String, input: JSONValue) async -> AgentToolOutput {
            executed.append(name)
            inputs[name] = input
            switch name {
            case "compare_periods":
                return .success(["currency": "USD", "type": "expense", "current": ["total": 820], "change_percent": -6])
            case "get_spending_summary":
                return .success(["currency": "USD", "type": "expense", "total": 820, "groups": [
                    ["key": "demo-category-groceries", "label": "Groceries", "total": 420],
                    ["key": "demo-category-dining", "label": "Eating out", "total": 400],
                ]])
            case "draft_transactions":
                return .success(["draft_id": "draft_1", "items": [], "skipped": [], "saved": false])
            default:
                return .failure("Unknown tool \(name).")
            }
        }
    }

    @Test func theMonthQuestionReadsTheMonthAndAnswersOnCards() async throws {
        let toolkit = DemoToolkit()
        let conversation = AgentConversation(transport: ScreenshotDemoTransport(script: script), toolkit: toolkit)

        let outcome = try await conversation.send(script.monthQuestion, context: "<app_context></app_context>")

        #expect(toolkit.executed == ["compare_periods", "get_spending_summary"])
        #expect(toolkit.inputs["get_spending_summary"]?["group_by"] == "category")
        #expect(outcome.reply.mood == .happy)
        #expect(outcome.reply.suggestions == script.suggestions)
        #expect(outcome.reply.blocks == [
            .text(script.intro),
            .metric(label: script.metricLabel, source: "r1", path: "current.total", trendPath: "change_percent"),
            .chart(kind: .donut, title: script.chartTitle, source: "r2", path: "groups"),
            .text(script.tip),
        ])
        // The cards resolve against the phone's own results.
        let metric = try #require(AgentReplyData.metric(label: script.metricLabel, source: "r1", path: "current.total",
                                                        trendPath: "change_percent", results: outcome.results))
        #expect(metric.value == .amount(820, currency: "USD"))
        #expect(metric.changePercent == -6)
        #expect(AgentReplyData.chart(source: "r2", path: "groups", results: outcome.results)?.groups.count == 2)
    }

    @Test func aRecordIsDraftedWithItsCard() async throws {
        let toolkit = DemoToolkit()
        let conversation = AgentConversation(transport: ScreenshotDemoTransport(script: script), toolkit: toolkit)

        let outcome = try await conversation.send("Spent 12 dollars on lunch")

        #expect(toolkit.executed == ["draft_transactions"])
        let item = try #require(toolkit.inputs["draft_transactions"]?["items"]?.arrayValue?.first)
        #expect(item["amount"] == .number(script.draftAmount))
        #expect(item["category"] == .string(script.draftCategory))
        #expect(outcome.reply.blocks == [.confirm(draftId: "draft_1")])
    }

    @Test func eachQuestionStartsItsOwnTurn() async throws {
        let toolkit = DemoToolkit()
        let conversation = AgentConversation(transport: ScreenshotDemoTransport(script: script), toolkit: toolkit)

        _ = try await conversation.send(script.monthQuestion)
        // The next question opens with the owed "shown" result of the reply before it.
        let outcome = try await conversation.send("coffee 1500")

        #expect(toolkit.executed == ["compare_periods", "get_spending_summary", "draft_transactions"])
        #expect(outcome.reply.blocks == [.confirm(draftId: "draft_1")])
    }
}

#endif
