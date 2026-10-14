//
//  AssistantNoticeCard.swift
//  Tenra
//
//  A message Ten wrote first (AssistantInbox): the mascot in the message's mood, its title and
//  text, "Go through it" (a question to the assistant, which spends a free answer) and a button
//  that hides it. Shown on Home while unread (AssistantNoticesSection), never in the chat.
//

import SwiftUI

struct AssistantNoticeCard: View {
    let notice: AssistantNotice
    let onAsk: () -> Void
    let onHide: () -> Void

    var body: some View {
        AssistantCard(title: nil) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                ParticleCreature(mood: notice.mood.creatureMood, style: .compact)
                    .frame(width: AssistantMetrics.headerMascot, height: AssistantMetrics.headerMascot)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(notice.title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.Text.primary)
                    Text(notice.body)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.Text.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "assistant.notice.hide"), systemImage: "xmark", action: onHide)
                    .labelStyle(.iconOnly)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.Text.tertiary)
                    .buttonStyle(.plain)
            }
            DSButton(String(localized: "assistant.notice.goThrough"), systemImage: "sparkles", appearance: .flat, size: .small, action: onAsk)
        }
        .accessibilityElement(children: .contain)
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
        if AssistantAvailability.isAvailable, let notice = unread.first {
            let title = String(localized: "assistant.notice.title")
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SectionHeader(unread.count > 1 ? "\(title) · \(unread.count)" : title)
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
            .animation(AppAnimation.smooth, value: notice.id)
        }
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
