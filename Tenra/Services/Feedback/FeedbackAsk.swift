//
//  FeedbackAsk.swift
//  Tenra
//
//  When Ten asks what the person thinks of Tenra (docs/domains/assistant.md §6, "Feedback").
//  The owner has no other way to hear from people: the app has no accounts and no analytics.
//  Ten asks on Home, in "Ten writes"; the answer is a short talk in Ten's chat, scripted on the
//  phone (AssistantViewModel.startFeedback), whose words go to the server's
//  `POST /v1/feedback`, not to the model.
//
//  The rounds are counted from the install day, so nothing needs storing: round 1 opens on the
//  third day for someone with five entries, the next every 45 days while the person still
//  records. Each round's message has its own key, and the inbox never posts a key twice, so a
//  round asks once, answered or hidden.
//

import Foundation

nonisolated enum FeedbackAsk {
    /// Days from the install to the first ask.
    static let firstAfterDays = 3
    /// Days between asks.
    static let everyDays = 45
    /// Entries before the first ask: someone who has not used Tenra has nothing to say yet.
    static let firstAfterEntries = 5
    /// A later round asks only someone who recorded within this many days.
    static let activeWithinDays = 14

    /// The round open now, or nil: too early, too few entries, or a later round for someone
    /// who stopped recording.
    static func round(installed: Date?, entries: Int, lastRecorded: Date?, now: Date) -> Int? {
        guard let installed, entries >= firstAfterEntries else { return nil }
        let days = now.timeIntervalSince(installed) / 86_400
        guard days >= Double(firstAfterDays) else { return nil }
        let round = 1 + Int((days - Double(firstAfterDays)) / Double(everyDays))
        if round > 1 {
            guard let lastRecorded,
                  now.timeIntervalSince(lastRecorded) <= Double(activeWithinDays) * 86_400 else { return nil }
        }
        return round
    }

    /// The key of a round's message in Ten's inbox.
    static func noticeID(round: Int) -> String { "feedback:\(round)" }

    /// The key of the message that opens the talk after the rating survey's "not really". It is
    /// never in the inbox: it only carries the talk to Ten's chat.
    static let surveyNoticeID = "feedback:survey"
}

extension AssistantNotices {
    /// Ten's "what do you think of Tenra?" for the round open now. Its button opens the
    /// feedback talk in Ten's chat (AssistantViewModel.startFeedback), which spends no answer.
    static func feedbackAsk(round: Int?, now: Date) -> AssistantNotice? {
        guard let round else { return nil }
        return AssistantNotice(
            id: FeedbackAsk.noticeID(round: round),
            kind: .feedback,
            title: String(localized: "feedback.notice.title"),
            body: String(localized: "feedback.notice.body"),
            mood: .idle,
            question: "",
            insightId: nil,
            createdAt: now
        )
    }

    /// What the rating survey's "not really" hands to Ten's chat: the same talk, with the first
    /// question already answered.
    static func feedbackAfterSurvey(now: Date) -> AssistantNotice {
        AssistantNotice(
            id: FeedbackAsk.surveyNoticeID,
            kind: .feedback,
            title: String(localized: "feedback.notice.title"),
            body: String(localized: "feedback.notice.body"),
            mood: .concerned,
            question: "",
            insightId: nil,
            createdAt: now
        )
    }
}
