//
//  AssistantNoticeCard.swift
//  Tenra
//
//  A message Ten wrote first (AssistantInbox): an adapter over DesignKit's NoticeCard (4.14.0),
//  the mascot in the message's mood at the card's picture size (NoticeCardMetrics, 5.2.0), its
//  title and text, "Go through it" (a question to the assistant, which spends a free answer)
//  and a button that hides it. Ten perks up once at a message it has not shown before. Shown
//  on Home while unread (AssistantNoticesSection), never in the chat.
//

import SwiftUI

struct AssistantNoticeCard: View {
    let notice: AssistantNotice
    let onAsk: () -> Void
    let onHide: () -> Void

    @Environment(\.amountsHidden) private var amountsHidden

    /// The last message Ten perked up at, so it does it once per message.
    @AppStorage("assistant.notice.perked") private var perkedNotice = ""
    @State private var perks = 0

    var body: some View {
        NoticeCard(
            title: notice.title,
            message: amountsHidden ? (notice.hiddenBody ?? notice.body) : notice.body,
            // The setup message opens the Wallet guide, an asset's a new valuation; the rest ask
            // Ten.
            actionTitle: actionTitle,
            actionSystemImage: actionSystemImage,
            action: onAsk,
            hideLabel: String(localized: "assistant.notice.hide"),
            onHide: onHide
        ) {
            ParticleCreature(mood: notice.mood.creatureMood, style: .compact)
                .creatureGesture(.perk, trigger: perks)
                .frame(width: NoticeCardMetrics.leadingSize, height: NoticeCardMetrics.leadingSize)
                .accessibilityHidden(true)
        }
        // A gesture plays when its trigger changes, never on appear: a moment after the card
        // settles.
        .task(id: notice.id) {
            guard perkedNotice != notice.id else { return }
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            perkedNotice = notice.id
            perks += 1
        }
    }
}

/// "Ten writes" on Home: the newest message Ten wrote that is not read, and how many wait
/// behind it. "Go through it" opens the assistant's tab, which asks the message's question
/// (AppCoordinator.goThrough); the setup message opens the Wallet guide and an asset's the
/// valuation sheet instead. "Hide" shows the next one. Nothing where the assistant does not run.
struct AssistantNoticesSection: View {
    @Environment(AppCoordinator.self) private var coordinator
    private let inbox = AssistantInbox.shared
    @State private var showingWalletGuide = false
    /// The asset an out-of-date message asked to value.
    @State private var valuingAsset: Asset?

    var body: some View {
        // A message about a subscription, a debt or a goal deleted since is not shown; the next
        // refresh drops it (AppCoordinator.refreshAssistantInbox).
        let subjects = coordinator.assistantNoticeSubjects
        let unread = inbox.unread.filter { subjects?.contains($0) ?? true }
        // The animation sits outside the conditional, so the section fades in and out (the
        // last one hidden) instead of making Home jump.
        Group {
            if AssistantAvailability.isAvailable, let notice = unread.first {
                section(notice: notice, count: unread.count)
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.smooth, value: unread.first?.id)
        // On the group, not the section: the setup message is read (gone) once its guide opens.
        .sheet(isPresented: $showingWalletGuide) {
            NavigationStack { WalletSetupGuideView() }
        }
        .sheet(item: $valuingAsset) { asset in
            let assetStore = coordinator.assetStore
            MoneyEntrySheet(
                title: asset.name,
                icon: asset.displayIcon,
                subtitle: String(localized: "asset.valuationHint"),
                currency: asset.currency,
                appSettings: coordinator.transactionsViewModel.appSettings,
                suggestedAmount: assetStore.summary(for: asset).value
            ) { amount, date, note in
                Task {
                    await assetStore.addValuation(AssetValuation(date: date, value: amount, source: .manual, note: note), to: asset.id)
                }
            }
        }
    }

    private func section(notice: AssistantNotice, count: Int) -> some View {
        let title = String(localized: "assistant.notice.title")
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(count > 1 ? "\(title) · \(count)" : title)
            AssistantNoticeCard(
                notice: notice,
                onAsk: {
                    HapticManager.light()
                    if notice.kind == .setup {
                        inbox.markRead(notice.id)
                        showingWalletGuide = true
                    } else if notice.kind == .asset {
                        inbox.markRead(notice.id)
                        valuingAsset = notice.subjectId.flatMap(coordinator.assetStore.asset(id:))
                    } else {
                        coordinator.goThrough(notice)
                    }
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

extension AssistantNoticeCard {
    private var actionTitle: String {
        switch notice.kind {
        case .setup: String(localized: "home.autoCapture.action")
        case .asset: String(localized: "asset.updateValue")
        default: String(localized: "assistant.notice.goThrough")
        }
    }

    private var actionSystemImage: String {
        switch notice.kind {
        case .setup: "wave.3.right"
        case .asset: "chart.line.uptrend.xyaxis"
        default: "sparkles"
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
        case .surprised: .surprised
        }
    }
}
