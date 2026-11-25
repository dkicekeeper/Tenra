//
//  AssistantChatDaysTests.swift
//  TenraTests
//
//  The chat's day lines (DesignKit's ConversationDivider): every message of a thread keeps when
//  it was added, in step with the messages through a failed turn, a trim and a relaunch; a kept
//  thread's questions come back with their days; a thread kept before the dates reads as before;
//  and a line goes over the first question of each day once the thread is not all from today.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantChatDaysTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 15 January 2027, 08:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let yesterday = now.addingTimeInterval(-86_400)
    private static let lastWeek = now.addingTimeInterval(-7 * 86_400)

    // MARK: - The conversation keeps the dates

    @Test func everyMessageKeepsWhenItWasAdded() async throws {
        let now = Self.now
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.toolUse("toolu_1", "get_accounts")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "r1")])],
        ])
        let conversation = AgentConversation(transport: transport, toolkit: FakeToolkit(), now: { now })

        _ = try await conversation.send("Сколько у меня денег?")

        #expect(conversation.messages.count == 4)
        #expect(conversation.dates == [Date?](repeating: now, count: 4))
        #expect(conversation.body.dates == conversation.dates)
        #expect(conversation.body.date(at: 0) == now)
        // The server gets the messages only.
        #expect(transport.calls.last?.count == 3)
    }

    @Test func aFailedTurnTakesItsDatesBack() async {
        let now = Self.now
        let conversation = AgentConversation(
            transport: ScriptedTransport([[AgentScript.done([], refused: true)]]),
            toolkit: FakeToolkit(),
            now: { now }
        )
        await #expect(throws: AgentConversationError.refused) {
            _ = try await conversation.send("…")
        }
        #expect(conversation.messages.isEmpty)
        #expect(conversation.dates.isEmpty)
    }

    @Test func trimmingKeepsTheDatesInStep() {
        let conversation = AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit())
        // 40 questions, a day apart: user (owed result + question), assistant (render_reply).
        var messages: [AgentWireMessage] = []
        var dates: [Date?] = []
        for index in 0..<40 {
            var content: [JSONValue] = []
            if index > 0 { content.append(AgentToolResult(toolUseId: "toolu_\(index - 1)", content: "shown", isError: false).block) }
            content.append(["type": "text", "text": .string("q\(index)")])
            let day = Self.lastWeek.addingTimeInterval(Double(index) * 86_400)
            messages.append(AgentWireMessage(role: .user, content: content))
            messages.append(AgentWireMessage(role: .assistant, content: [AgentScript.render("toolu_\(index)", source: "none")]))
            dates.append(contentsOf: [day, day])
        }
        conversation.restore(AgentThreadSnapshot.Body(messages: messages, results: [:], owedResults: [], dates: dates))

        #expect(conversation.trimIfNeeded())
        #expect(conversation.dates.count == conversation.messages.count)
        // The history now starts at q10, and so do its dates.
        #expect(conversation.messages.first?.content.first?["text"] == "q10")
        #expect(conversation.dates.first == Self.lastWeek.addingTimeInterval(10 * 86_400))
    }

    // MARK: - A kept thread

    @Test func aThreadKeptBeforeTheDatesHasNone() throws {
        let old = Data(#"{"messages":[{"role":"user","content":[{"type":"text","text":"Привет"}]}],"results":{},"owedResults":[],"local":[{"position":1,"question":"кофе 1500","draftId":"draft_1"}]}"#.utf8)
        let body = try JSONDecoder().decode(AgentThreadSnapshot.Body.self, from: old)
        #expect(body.dates.isEmpty)
        #expect(body.date(at: 0) == nil)
        #expect(body.local.first?.date == nil)

        let conversation = AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit())
        conversation.restore(body)
        #expect(conversation.dates == [nil])

        // Their entries have no day, so no line is drawn over them.
        let entries = AssistantViewModel.entries(replaying: body)
        #expect(entries.compactMap(\.question) == ["Привет", "кофе 1500"])
        #expect(entries.allSatisfy { $0.date == nil })
        #expect(AssistantViewModel.dayStarts(in: entries, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test func aKeptThreadsQuestionsComeBackWithTheirDays() throws {
        let body = AgentThreadSnapshot.Body(
            messages: [
                .userText(["Сколько у меня денег?"]),
                AgentWireMessage(role: .assistant, content: [AgentScript.render("toolu_1", source: "none")]),
                .userText(["А на кафе?"]),
                AgentWireMessage(role: .assistant, content: [AgentScript.render("toolu_2", source: "none")]),
            ],
            results: [:],
            owedResults: [],
            local: [AgentThreadSnapshot.LocalExchange(position: 4, question: "кофе 1500", draftId: "draft_1", date: Self.now)],
            dates: [Self.lastWeek, Self.lastWeek, Self.yesterday, Self.yesterday]
        )
        let again = try JSONDecoder().decode(AgentThreadSnapshot.Body.self, from: JSONEncoder().encode(body))
        #expect(again == body)

        let entries = AssistantViewModel.entries(replaying: again)
        let questions = entries.filter { $0.question != nil }
        #expect(questions.map(\.question) == ["Сколько у меня денег?", "А на кафе?", "кофе 1500"])
        #expect(questions.map(\.date) == [Self.lastWeek, Self.yesterday, Self.now])
        // A reply has no day of its own.
        #expect(entries.filter { $0.question == nil }.allSatisfy { $0.date == nil })
    }

    @Test func aDateIsNoMentionOfAFact() {
        let body = AgentThreadSnapshot.Body(
            messages: [.userText(["Привет"])],
            results: [:],
            owedResults: [],
            dates: [Date(timeIntervalSinceReferenceDate: 1500)]
        )
        #expect(!body.mentions(["1500"]))
        #expect(body.mentions(["привет"]))
    }

    // MARK: - Where the lines go

    @Test func aThreadAllFromTodayHasNoLines() {
        let entries = [
            question(at: Self.now.addingTimeInterval(-3600)),
            reply(),
            question(at: Self.now),
            reply(),
        ]
        #expect(AssistantViewModel.dayStarts(in: entries, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test func eachDayStartsAtItsFirstQuestion() {
        let first = question(at: Self.yesterday)
        let sameDay = question(at: Self.yesterday.addingTimeInterval(600))
        let attachment = AssistantViewModel.Entry(
            id: UUID(),
            content: .attachment(AgentAttachmentSummary(kind: .receipt, title: "Магазин", count: 1, skipped: 0, uncategorized: 0, moves: 0, byCategory: [])),
            date: Self.now
        )
        let today = question(at: Self.now.addingTimeInterval(60))
        let entries = [first, reply(), sameDay, reply(), attachment, today, reply()]

        let starts = AssistantViewModel.dayStarts(in: entries, now: Self.now, calendar: Self.calendar)

        #expect(starts == [first.id: Self.yesterday, attachment.id: Self.now])
    }

    @Test func todayAfterAnUndatedThreadStartsADay() {
        let old = AssistantViewModel.Entry(id: UUID(), content: .question("Привет"))
        let today = question(at: Self.now)
        let entries = [old, reply(), today, reply()]

        #expect(AssistantViewModel.dayStarts(in: entries, now: Self.now, calendar: Self.calendar) == [today.id: Self.now])
    }

    // MARK: - Helpers

    private func question(at date: Date) -> AssistantViewModel.Entry {
        AssistantViewModel.Entry(id: UUID(), content: .question("Вопрос"), date: date)
    }

    private func reply() -> AssistantViewModel.Entry {
        AssistantViewModel.Entry(id: UUID(), content: .reply(AgentReply(blocks: [.text("Ответ")], mood: .happy, suggestions: []), results: [:]))
    }
}
