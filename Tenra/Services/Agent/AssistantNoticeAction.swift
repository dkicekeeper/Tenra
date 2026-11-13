//
//  AssistantNoticeAction.swift
//  Tenra
//
//  What the person can do about a message Ten wrote with one tap (docs/plan-ten-agent.md stage
//  4): "Pause" on a subscription charged tomorrow, "Mark settled" on a debt due tomorrow. The
//  phone makes the draft by rule, without the model, so it spends no answer and works where the
//  cloud does not answer; nothing is written until the person confirms the draft's card in
//  Ten's chat (AssistantViewModel.startDraft), and Undo takes it back.
//

import Foundation

struct AssistantNoticeAction {
    /// The button's title, which also stands as the person's message in the chat.
    let title: String
    let operations: [AgentDraftOperation]

    /// The title of the action a message of this kind has, if any.
    static func title(for notice: AssistantNotice) -> String? {
        switch notice.kind {
        case .charge: return String(localized: "assistant.notice.pause")
        case .debt: return String(localized: "assistant.notice.settle")
        default: return nil
        }
    }

    /// The action as a draft, or nil when what the message was about is gone or no longer in
    /// the state the action is for (the subscription paused, the debt settled).
    init?(notice: AssistantNotice, series: [RecurringSeries], debts: [PersonalDebt], now: Date) {
        guard let title = Self.title(for: notice) else { return nil }
        switch notice.kind {
        case .charge:
            guard let subscription = series.first(where: { $0.id == notice.subjectId }),
                  subscription.isSubscription, subscription.subscriptionStatus == .active else { return nil }
            operations = [.subscriptionState(series: subscription, pause: true)]
        case .debt:
            guard let before = debts.first(where: { $0.id == notice.subjectId }), !before.isSettled else { return nil }
            var after = before
            after.settledAt = now
            operations = [.debtChange(before: before, after: after)]
        default:
            return nil
        }
        self.title = title
    }
}
