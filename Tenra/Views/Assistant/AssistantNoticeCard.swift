//
//  AssistantNoticeCard.swift
//  Tenra
//
//  A message Ten wrote first (AssistantInbox): the mascot in the message's mood, its title and
//  text, "Go through it" (a question to the assistant, which spends a free answer) and a button
//  that hides it. Shown in the chat while unread.
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
