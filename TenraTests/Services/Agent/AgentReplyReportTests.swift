//
//  AgentReplyReportTests.swift
//  TenraTests
//
//  Pins "Не то" under Ten's answers (AgentReplyReport, docs/domains/assistant.md §7): the
//  exchange carries the question and Ten's words, the cards only by kind; the message falls back
//  to the reason's words; only the latest answer the model wrote can be reported, never a line
//  the phone wrote itself. All data invented.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentReplyReportTests {

    private let reply = AgentReply(
        blocks: [
            .text("Траты на **кафе выросли**."),
            .metric(label: "Кафе, октябрь 45 000", source: "r1", path: "total", trendPath: nil),
            .text("  "),
            .confirm(draftId: "draft_1"),
            .metric(label: "Кафе, сентябрь", source: "r2", path: "total", trendPath: nil),
            .text("Можно поставить лимит."),
        ],
        mood: .concerned,
        suggestions: []
    )

    @Test("The exchange: the question, Ten's words in order, the cards by kind once, no labels or figures")
    func exchange() {
        let exchange = AgentReplyReport.exchange(question: "  Сколько я трачу на кафе?  ", reply: reply)
        #expect(exchange.question == "Сколько я трачу на кафе?")
        #expect(exchange.answer == "Траты на **кафе выросли**.\n\nМожно поставить лимит.")
        #expect(exchange.cards == ["metric", "confirm"])
        #expect(!exchange.answer.contains("45 000"))
    }

    @Test("Within the server's limits")
    func limits() {
        let long = AgentReply(blocks: [.text(String(repeating: "а", count: 5000))], mood: .idle, suggestions: [])
        let exchange = AgentReplyReport.exchange(question: String(repeating: "в", count: 3000), reply: long)
        #expect(exchange.question.count == AgentReplyReport.questionLimit)
        #expect(exchange.answer.count == AgentReplyReport.answerLimit)
    }

    @Test("The message: the person's words, or the reason's when they wrote none")
    func message() {
        let exchange = AgentReplyReport.exchange(question: "Вопрос", reply: reply)
        let typed = AgentReplyReport.message(reason: .wrong, comment: "  Лимит не тот  ", exchange: exchange)
        #expect(typed == AgentFeedbackMessage(text: "Лимит не тот", mood: .bad, source: .reply, reason: .wrong, exchange: exchange))
        let silent = AgentReplyReport.message(reason: .notDone, comment: " ", exchange: exchange)
        #expect(silent.text == AgentReplyReport.title(of: .notDone))
        #expect(!silent.text.isEmpty)
    }

    @Test("Only the latest answer the model wrote, once nothing is coming")
    func reportable() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "r1")])],
        ])
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            access: .unlimited
        )
        #expect(model.reportableReply == nil)
        await model.send("Сколько у меня денег?")
        let answer = model.entries.last
        #expect(model.reportableReply == answer?.id)
        if let id = answer?.id {
            let exchange = model.reportExchange(for: id)
            #expect(exchange?.question == "Сколько у меня денег?")
            #expect(exchange?.answer == "Всего на счетах")
            #expect(exchange?.cards == ["metric"])
            model.markReported(id)
            #expect(model.reportedReplies.contains(id))
        }
    }
}
