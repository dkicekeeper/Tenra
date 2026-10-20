//
//  ScreenshotDemoTransportTests.swift
//  TenraTests
//
//  Ten's scripted server for the screenshot capture: each of the demo's questions calls its own
//  tool, and the reply over that tool's result decodes into the cards the frame shows. A
//  mistake here costs an hour-long capture run that shows the wrong answer.
//

#if DEBUG

import Foundation
import Testing
@testable import Tenra

struct ScreenshotDemoTransportTests {

    private static let reply = ScreenshotDemoReply(
        text: "Spending", metricLabel: "Expenses", chartTitle: "My spending this month",
        suggestions: ["Compare"], from: "2026-10-01", to: "2026-10-19",
        subscriptionsQuestion: "What do my subscriptions cost?", subscriptionsText: "Subscriptions",
        subscriptionsLabel: "Per month",
        currenciesQuestion: "How much money do I have in all currencies?", currenciesText: "Currencies",
        currenciesTotalLabel: "Total", savingsLabel: "Savings EUR",
        loanQuestion: "What if I pay $1,100 off my loan early?", loanText: "Loan", loanOneOff: 1_100,
        loanInterestLabel: "Interest saved", loanMonthsLabel: "Months sooner"
    )

    /// The person's message as the phone sends it: its context first, the question last.
    private static func ask(_ question: String) -> [AgentWireMessage] {
        [.userText(["Today is 2026-10-19.", question])]
    }

    /// The question, the model's tool call, and the phone's result for it.
    private static func answered(_ question: String, result: JSONValue) throws -> [AgentWireMessage] {
        var result = result
        if case .object(var object) = result {
            object[AgentProtocol.resultIdKey] = "r1"
            result = .object(object)
        }
        let content = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        return ask(question) + [
            AgentWireMessage(role: .assistant, content: [["type": "tool_use", "id": "demo_1", "name": "tool", "input": [:]]]),
            AgentWireMessage(role: .user, content: [["type": "tool_result", "tool_use_id": "demo_1", "content": .string(content)]]),
        ]
    }

    private static func call(in events: [AgentStreamEvent]) -> JSONValue? {
        for case .done(let done) in events {
            return done.content.first
        }
        return nil
    }

    private static func renderedReply(_ events: [AgentStreamEvent]) throws -> AgentReply {
        let render = try #require(Self.call(in: events))
        #expect(render["name"] == .string(AgentProtocol.renderReplyTool))
        let input = try #require(render["input"])
        return try JSONDecoder().decode(AgentReply.self, from: JSONEncoder().encode(input))
    }

    @Test func eachQuestionCallsItsTool() {
        let tools = [
            Self.reply.chartTitle: "get_spending_summary",
            Self.reply.subscriptionsQuestion: "list_recurring",
            Self.reply.currenciesQuestion: "get_accounts",
            Self.reply.loanQuestion: "simulate_loan",
        ]
        for (question, tool) in tools {
            let call = Self.call(in: ScreenshotDemoTransport.events(for: Self.ask(question), reply: Self.reply))
            #expect(call?["name"] == .string(tool), "\(question)")
        }
        let loan = Self.call(in: ScreenshotDemoTransport.events(for: Self.ask(Self.reply.loanQuestion), reply: Self.reply))
        #expect(loan?.value(atPath: "input.account_id") == .string(ScreenshotDemoReply.loanAccountId))
        #expect(loan?.value(atPath: "input.one_off") == .number(1_100))
        // The capture taps the presets in this order.
        #expect(Self.reply.questions == [
            Self.reply.chartTitle, Self.reply.subscriptionsQuestion, Self.reply.currenciesQuestion, Self.reply.loanQuestion,
        ])
    }

    @Test func subscriptionsShowTheMonthlyTotalAndTheList() throws {
        let messages = try Self.answered(Self.reply.subscriptionsQuestion, result: ["currency": "USD", "items": []])
        let reply = try Self.renderedReply(ScreenshotDemoTransport.events(for: messages, reply: Self.reply))
        #expect(reply.blocks == [
            .text("Subscriptions"),
            .metric(label: "Per month", source: "r1", path: "subscriptions_monthly_total_base", trendPath: nil),
            .recurring(source: "r1"),
        ])
    }

    @Test func currenciesPointAtTheSavingsAccount() throws {
        let result: JSONValue = [
            "currency": "USD",
            "total_base": 5_000,
            "accounts": [
                ["id": "demo-account-card", "currency": "USD", "balance": 1_000],
                ["id": .string(ScreenshotDemoReply.savingsAccountId), "currency": "EUR", "balance": 800],
            ],
        ]
        let messages = try Self.answered(Self.reply.currenciesQuestion, result: result)
        let reply = try Self.renderedReply(ScreenshotDemoTransport.events(for: messages, reply: Self.reply))
        #expect(reply.blocks == [
            .text("Currencies"),
            .metric(label: "Total", source: "r1", path: "total_base", trendPath: nil),
            .metric(label: "Savings EUR", source: "r1", path: "accounts.1.balance", trendPath: nil),
        ])
        // The savings card is in its own currency.
        let savings = AgentReplyData.metric(label: "Savings EUR", source: "r1", path: "accounts.1.balance", trendPath: nil, results: ["r1": result])
        #expect(savings?.value == .amount(800, currency: "EUR"))
    }

    @Test func theLoanShowsInterestAndMonthsSaved() throws {
        let messages = try Self.answered(Self.reply.loanQuestion, result: ["currency": "USD", "interest_saved": 120, "months_saved": 4])
        let reply = try Self.renderedReply(ScreenshotDemoTransport.events(for: messages, reply: Self.reply))
        #expect(reply.mood == .proud)
        #expect(reply.blocks == [
            .text("Loan"),
            .metric(label: "Interest saved", source: "r1", path: "interest_saved", trendPath: nil),
            .metric(label: "Months sooner", source: "r1", path: "months_saved", trendPath: nil),
        ])
    }

    @Test func anyOtherQuestionGetsTheMonthsSpending() throws {
        let call = Self.call(in: ScreenshotDemoTransport.events(for: Self.ask("Hello"), reply: Self.reply))
        #expect(call?["name"] == "get_spending_summary")
        let messages = try Self.answered("Hello", result: ["currency": "USD", "total": 900, "groups": []])
        let reply = try Self.renderedReply(ScreenshotDemoTransport.events(for: messages, reply: Self.reply))
        #expect(reply.blocks.count == 3)
        #expect(reply.mood == .happy)
    }
}

#endif
