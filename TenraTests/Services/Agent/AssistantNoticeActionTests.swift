//
//  AssistantNoticeActionTests.swift
//  TenraTests
//
//  The one-tap action of a message Ten wrote (AssistantNoticeAction): a charge that comes
//  tomorrow drafts a pause of its subscription, a debt due tomorrow drafts it settled, and a
//  message whose subject is gone, or of another kind, has no action.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantNoticeActionTests {

    private static let now = FastDateParser.date(from: "2026-11-13")!.addingTimeInterval(12 * 3600)

    private static func notice(_ kind: AssistantNotice.Kind, subject: String?) -> AssistantNotice {
        AssistantNotice(
            id: "\(kind.rawValue):\(subject ?? "none")", kind: kind, title: "Title", body: "Body", mood: .idle,
            question: "Question", insightId: nil, subjectId: subject, createdAt: now
        )
    }

    private static let spotify = RecurringSeries(
        id: "rec_spotify", amount: 2_990, currency: "KZT", category: "Подписки", description: "Spotify",
        accountId: "acc_kaspi", frequency: .monthly, startDate: "2026-09-14", kind: .subscription, status: .active
    )

    @Test func aChargeDraftsAPauseOfItsSubscription() throws {
        let action = try #require(AssistantNoticeAction(
            notice: Self.notice(.charge, subject: "rec_spotify"), series: [Self.spotify], debts: [], now: Self.now
        ))
        #expect(action.title == String(localized: "assistant.notice.pause"))
        #expect(action.operations == [.subscriptionState(series: Self.spotify, pause: true)])

        // Paused since, or deleted: nothing to offer.
        var paused = Self.spotify
        paused.status = .paused
        #expect(AssistantNoticeAction(notice: Self.notice(.charge, subject: "rec_spotify"), series: [paused], debts: [], now: Self.now) == nil)
        #expect(AssistantNoticeAction(notice: Self.notice(.charge, subject: "rec_gone"), series: [Self.spotify], debts: [], now: Self.now) == nil)
    }

    @Test func aDebtDueDraftsItSettled() throws {
        let debt = PersonalDebt(id: "d_askhat", direction: .owedToMe, person: "Асхат", amount: 50_000, currency: "KZT")
        let action = try #require(AssistantNoticeAction(
            notice: Self.notice(.debt, subject: "d_askhat"), series: [], debts: [debt], now: Self.now
        ))
        guard case .debtChange(let before, let after)? = action.operations.first else {
            Issue.record("expected a debt change")
            return
        }
        #expect(before == debt)
        #expect(after.settledAt == Self.now)

        var settled = debt
        settled.settledAt = Self.now
        #expect(AssistantNoticeAction(notice: Self.notice(.debt, subject: "d_askhat"), series: [], debts: [settled], now: Self.now) == nil)
    }

    @Test func otherMessagesHaveNoAction() {
        #expect(AssistantNoticeAction.title(for: Self.notice(.signal, subject: nil)) == nil)
        #expect(AssistantNoticeAction(notice: Self.notice(.goal, subject: "g"), series: [], debts: [], now: Self.now) == nil)
    }
}
