//
//  AssistantNoticeTextTests.swift
//  TenraTests
//
//  What a kept message of Ten's may be written again from (AssistantNoticeText): only a format
//  that still takes exactly its values and still resolves, so a later version that changes a
//  stored key's arguments or drops it keeps the stored words; a value case another version does
//  not know drops only that message's values; and a message kept before the values existed takes
//  a fresh message's words only from the same day.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantNoticeTextTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func inbox(_ defaults: UserDefaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!) -> AssistantInbox {
        AssistantInbox(defaults: defaults)
    }

    private static func notice(
        id: String = "charge:s1:2027-01-15",
        body: String = "Kept words",
        text: AssistantNoticeText?,
        createdAt: Date = now
    ) -> AssistantNotice {
        AssistantNotice(
            id: id, kind: .charge, title: "Netflix", body: body, hiddenBody: "Kept hidden",
            text: text, mood: .idle, question: "", insightId: nil, createdAt: createdAt
        )
    }

    @Test func argumentsAreCountedAsTheFormatTakesThem() {
        #expect(AssistantNoticeText.objectArguments(in: "Charged tomorrow: %@") == 1)
        #expect(AssistantNoticeText.objectArguments(in: "%2$@ by %1$@, 100%%") == 2)
        #expect(AssistantNoticeText.objectArguments(in: "%1$@ and %1$@ again") == 1)
        #expect(AssistantNoticeText.objectArguments(in: "no arguments") == 0)
        // A number, a mix of positional and plain, a gap: never filled with strings.
        #expect(AssistantNoticeText.objectArguments(in: "%lld left") == nil)
        #expect(AssistantNoticeText.objectArguments(in: "%1$@ and %@") == nil)
        #expect(AssistantNoticeText.objectArguments(in: "%1$@ and %3$@") == nil)
    }

    /// A later version gave the key one more argument: the stored words stay (no garbage read
    /// past the arguments).
    @Test func aFormatWithMoreArgumentsThanValuesKeepsTheStoredWords() {
        let text = AssistantNoticeText(format: "assistant.notice.goal.behind", values: [.amount(1_000, currency: "KZT")])
        #expect(text.body == nil)
        let inbox = Self.inbox()
        inbox.post([Self.notice(text: text)], now: Self.now)
        inbox.rewriteTexts(from: [])
        #expect(inbox.notices.first?.body == "Kept words")
        #expect(inbox.notices.first?.hiddenBody == "Kept hidden")
    }

    @Test func aFormatWithFewerArgumentsThanValuesKeepsTheStoredWords() {
        let text = AssistantNoticeText(format: "assistant.notice.charge", values: [.amount(1_000, currency: "KZT"), .text("extra")])
        let inbox = Self.inbox()
        inbox.post([Self.notice(text: text)], now: Self.now)
        inbox.rewriteTexts(from: [])
        #expect(inbox.notices.first?.body == "Kept words")
    }

    /// A later version renamed or removed the key: the stored words stay, not the raw key.
    @Test func anUnknownKeyKeepsTheStoredWords() {
        let text = AssistantNoticeText(format: "assistant.notice.removedInALaterVersion", values: [.amount(1_000, currency: "KZT")])
        let inbox = Self.inbox()
        inbox.post([Self.notice(text: text)], now: Self.now)
        inbox.rewriteTexts(from: [])
        #expect(inbox.notices.first?.body == "Kept words")
    }

    /// A value case this version does not know (a later one wrote it): the message and the
    /// posted keys come back, only its values are gone.
    @Test func anUnknownValueCaseDropsOnlyThatMessagesValues() throws {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let text = AssistantNoticeText(format: "assistant.notice.charge", values: [.amount(4_990, currency: "KZT")])
        let first = Self.inbox(defaults)
        first.post([Self.notice(text: text), Self.notice(id: "charge:s2:2027-01-15", text: text)], now: Self.now)

        let key = "assistant.inbox.v1"
        let data = try #require(defaults.data(forKey: key))
        var stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var notices = try #require(stored["notices"] as? [[String: Any]])
        var future = try #require(notices[0]["text"] as? [String: Any])
        future["values"] = [["percent": ["_0": 12.5]]]
        notices[0]["text"] = future
        stored["notices"] = notices
        defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: key)

        let again = Self.inbox(defaults)
        try #require(again.notices.count == 2)
        #expect(again.notices[0].text == nil)
        #expect(again.notices[0].body == "Kept words")
        #expect(again.notices[1].text == text)
        // The posted keys survived too: nothing posts twice.
        again.post([Self.notice(text: text)], now: Self.now)
        #expect(again.notices.count == 2)
    }

    /// A message kept before the values existed takes a fresh message's words only when both are
    /// of the same day: a key that repeats on another day may carry other figures.
    @Test func aMessageWithoutValuesTakesOnlyTheSameDaysWords() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Self.now)!
        let fresh = Self.notice(id: "signal:over", body: "Today's words", text: nil, createdAt: Self.now)

        let older = Self.inbox()
        older.post([Self.notice(id: "signal:over", body: "Yesterday's words", text: nil, createdAt: yesterday)], now: yesterday)
        older.rewriteTexts(from: [fresh])
        #expect(older.notices.first?.body == "Yesterday's words")

        let sameDay = Self.inbox()
        sameDay.post([Self.notice(id: "signal:over", body: "This morning's words", text: nil, createdAt: Self.now)], now: Self.now)
        sameDay.rewriteTexts(from: [fresh])
        #expect(sameDay.notices.first?.body == "Today's words")
    }
}
