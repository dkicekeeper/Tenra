//
//  AssistantNoticeCard.swift
//  Tenra
//
//  A message Ten wrote first (AssistantInbox): an adapter over DesignKit's NoticeCard (4.14.0),
//  the mascot in the message's mood, its title and text, "Go through it" (a question to the
//  assistant, which spends a free answer) and a button that hides it. Shown on Home while
//  unread (AssistantNoticesSection), never in the chat.
//

import SwiftUI

struct AssistantNoticeCard: View {
    let notice: AssistantNotice
    let onAsk: () -> Void
    let onHide: () -> Void

    var body: some View {
        NoticeCard(
            title: notice.title,
            message: notice.body,
            actionTitle: String(localized: "assistant.notice.goThrough"),
            actionSystemImage: "sparkles",
            action: onAsk,
            hideLabel: String(localized: "assistant.notice.hide"),
            onHide: onHide
        ) {
            ParticleCreature(mood: notice.mood.creatureMood, style: .compact)
                .frame(width: AssistantMetrics.headerMascot, height: AssistantMetrics.headerMascot)
                .accessibilityHidden(true)
        }
    }
}

/// "Ten writes" on Home: the newest message Ten wrote that is not read, and how many wait
/// behind it. "Go through it" opens the assistant's tab, which asks the message's question
/// (AppCoordinator.goThrough); "Hide" shows the next one. Nothing where the assistant does not
/// run.
struct AssistantNoticesSection: View {
    @Environment(AppCoordinator.self) private var coordinator
    private let inbox = AssistantInbox.shared

    var body: some View {
        let unread = inbox.unread
        // The animation sits outside the conditional, so the section fades in and out (the
        // last one hidden) instead of making Home jump.
        Group {
            if AssistantAvailability.isAvailable, let notice = unread.first {
                section(notice: notice, count: unread.count)
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.smooth, value: unread.first?.id)
    }

    private func section(notice: AssistantNotice, count: Int) -> some View {
        let title = String(localized: "assistant.notice.title")
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(count > 1 ? "\(title) · \(count)" : title)
            AssistantNoticeCard(
                notice: notice,
                onAsk: {
                    HapticManager.light()
                    coordinator.goThrough(notice)
                },
                onHide: { inbox.markRead(notice.id) }
            )
            .id(notice.id)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenPadding()
    }
}

extension AssistantNotice.Mood {
    var creatureMood: ParticleCreature.Mood {
        switch self {
        case .idle: .idle
        case .happy: .happy
        case .concerned: .worried
        case .celebrate: .celebrating
        }
    }
}
