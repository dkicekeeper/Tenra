//
//  FeedbackAskTests.swift
//  TenraTests
//
//  When Ten asks what the person thinks of Tenra (FeedbackAsk): rounds counted from the install.
//

import Foundation
import Testing
@testable import Tenra

@Suite("FeedbackAsk")
@MainActor
struct FeedbackAskTests {
    private static let installed = Date(timeIntervalSince1970: 1_800_000_000)

    private static func day(_ days: Double) -> Date {
        installed.addingTimeInterval(days * 86_400)
    }

    @Test("The first round opens on the third day for someone with five entries")
    func firstRound() {
        let entries = FeedbackAsk.firstAfterEntries
        #expect(FeedbackAsk.round(installed: Self.installed, entries: entries, lastRecorded: nil, now: Self.day(2.9)) == nil)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: entries - 1, lastRecorded: nil, now: Self.day(10)) == nil)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: entries, lastRecorded: nil, now: Self.day(3)) == 1)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: entries, lastRecorded: nil, now: Self.day(47.9)) == 1)
        #expect(FeedbackAsk.round(installed: nil, entries: 100, lastRecorded: nil, now: Self.day(10)) == nil)
    }

    @Test("A later round opens every 45 days, only for someone who still records")
    func laterRounds() {
        let now = Self.day(48)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: 40, lastRecorded: Self.day(47), now: now) == 2)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: 40, lastRecorded: Self.day(48.0 - 14.5), now: now) == nil)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: 40, lastRecorded: nil, now: now) == nil)
        #expect(FeedbackAsk.round(installed: Self.installed, entries: 40, lastRecorded: Self.day(200), now: Self.day(201)) == 5)
    }

    @Test("Each round's message has its own key")
    func noticeKeys() throws {
        #expect(FeedbackAsk.noticeID(round: 1) != FeedbackAsk.noticeID(round: 2))
        #expect(AssistantNotices.feedbackAsk(round: nil, now: Self.installed) == nil)
        let notice = try #require(AssistantNotices.feedbackAsk(round: 3, now: Self.installed))
        #expect(notice.id == FeedbackAsk.noticeID(round: 3))
        #expect(notice.kind == .feedback)
    }

    @Test("Only the open round's message stays in Ten's inbox")
    func subjects() throws {
        let old = try #require(AssistantNotices.feedbackAsk(round: 1, now: Self.installed))
        let open = try #require(AssistantNotices.feedbackAsk(round: 2, now: Self.installed))
        var subjects = AssistantNotices.Subjects(subscriptions: [], debts: [], goals: [])
        #expect(subjects.contains(old))
        subjects.feedbackRound = 2
        #expect(!subjects.contains(old))
        #expect(subjects.contains(open))
    }
}
