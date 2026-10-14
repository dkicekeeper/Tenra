//
//  AssistantView.swift
//  Tenra
//
//  The assistant's home, the action tab's page (docs/plan-ai-assistant.md §1, §3.6): Ten in the
//  greeting, ready-made questions (or questions about the screen "Ask Ten" came from,
//  AssistantEntryPoints), the latest chats and the field. Whatever goes from here starts a new
//  chat, pushed as a page of its own (AssistantChatView): a question, a voice message, an
//  attachment, "Go through it" on a message Ten wrote on Home (AssistantNoticesSection), a
//  file opened in Tenra. A chat in the list opens again; a long press deletes it. The chat
//  open last stays at the top of the list, written or not.
//
//  Nothing leaves the phone before the person agrees: the first question opens the consent
//  sheet (App Review 5.1.2(i)) and goes once they turn the cloud mode on; a plain record is
//  drafted on the phone and needs none (FastPath).
//
//  The field carries what used to sit behind "+" (§3.8): the paperclip's menu attaches a
//  receipt (scanner or photos) or a statement (PDF, or CSV into its own import flow), read on
//  the phone into a summary card (AssistantAttachmentSources, AssistantAttachmentCard); the
//  microphone (while the field is empty) opens the voice sheet, whose words go as a message
//  (AssistantVoiceSheet).
//

import SwiftUI

/// A page on the assistant's stack.
enum AssistantPage: Hashable {
    /// The open chat (AssistantViewModel's thread).
    case chat
}

struct AssistantView: View {
    let model: AssistantViewModel

    @Environment(PremiumManager.self) private var premium
    @Environment(AppCoordinator.self) private var coordinator
    @State private var path = NavigationPath()
    @State private var draft = ""
    @State private var showingVoice = false
    @State private var attachmentSource: AssistantAttachmentSource?
    @State private var readingAttachment = false
    @State private var attachmentError: String?
    /// Questions about the screen the assistant was opened from.
    @State private var topicQuestions: [String] = []
    @State private var showingPaywall = false
    @State private var showingConsent = false
    /// What waits for the cloud consent.
    @State private var awaitingConsent: Start?
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @FocusState private var composerFocused: Bool
    // Ten's lines and gestures on the home (AssistantChatter).
    @AppStorage(AssistantChatter.enabledKey) private var chatterOn = true
    @AppStorage(AssistantChatter.greetedDayKey) private var greetedDay = ""
    @State private var speech: CreatureSpeech?
    @State private var gesture: CreatureGesture = .wave
    @State private var gestureCount = 0
    @State private var taps: [Date] = []
    @State private var tapCount = 0
    @State private var tapLineTurn = 0
    @State private var lastTapLine = Date.distantPast

    /// What starts a new chat and needs the cloud.
    enum Start: Equatable {
        case question(String, spoken: Bool)
        case notice(AssistantNotice)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                greeting
                    .screenPadding()
                    .padding(.vertical, AppSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            // A tap anywhere puts the keyboard away (buttons still work).
            .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
            .safeAreaBar(edge: .bottom) {
                AssistantComposerBar(
                    model: model,
                    draft: $draft,
                    focus: $composerFocused,
                    readingAttachment: readingAttachment,
                    attachmentError: attachmentError,
                    onAttach: { source in
                        attachmentError = nil
                        attachmentSource = source
                    },
                    onVoice: { showingVoice = true },
                    onPaywall: { showingPaywall = true },
                    onSend: { start(.question(draft, spoken: false)) }
                )
            }
            .navigationTitle(String(localized: "tab.assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AssistantPage.self) { page in
                switch page {
                case .chat: AssistantChatView(model: model)
                }
            }
            .navigationDestination(for: AssistantRoute.self) { route in
                AssistantDestinationView(route: route)
            }
        }
        .assistantAttachmentSources(
            source: $attachmentSource,
            reading: $readingAttachment,
            takesHandedOverFiles: true,
            onRead: { attachment, summary in
                HapticManager.success()
                // An attachment from here, or a file opened in Tenra, starts a chat of its own.
                if !model.isWorking { model.reset() }
                model.attach(attachment, summary: summary)
                showChat()
            },
            onFailure: { message in
                HapticManager.error()
                attachmentError = message
            }
        )
        .assistantConsent(
            isPresented: $showingConsent,
            onAllow: {
                if let pending = awaitingConsent {
                    awaitingConsent = nil
                    start(pending)
                }
            },
            onDecline: { awaitingConsent = nil }
        )
        .paywallSheet(isPresented: $showingPaywall) {
            model.refreshAllowance()
        }
        .sheet(isPresented: $showingVoice) {
            AssistantVoiceSheet { start(.question($0, spoken: true)) }
        }
        .onAppear { model.refreshAllowance() }
        .task { await model.restore() }
        // Back on the home: the chat just left is in the list.
        .onChange(of: path.isEmpty) { _, isHome in
            if isHome { Task { await model.refreshRecent() } }
        }
        .onChange(of: premium.isPro) { model.refreshAllowance() }
        // "Ask Ten" on an account, a category, an insight or the history.
        .onChange(of: coordinator.assistantTopic, initial: true) { _, topic in
            guard topic != nil, let topic = coordinator.consumeAssistantTopic() else { return }
            path = NavigationPath()
            topicQuestions = topic.questions
        }
        // "Go through it" on Home.
        .onChange(of: coordinator.pendingNotice, initial: true) { _, notice in
            guard notice != nil, let notice = coordinator.consumePendingNotice() else { return }
            start(.notice(notice))
        }
    }

    // MARK: - Pieces

    private var greeting: some View {
        VStack(spacing: AppSpacing.lg) {
            ParticleCreature(mood: AssistantMetrics.mood(for: model), isInteractive: true,
                             speech: chatterOn ? speech : nil)
                .creatureGesture(gesture, trigger: gestureCount)
                // A life of its own (DesignKit 4.11): it looks round, stretches, dozes off when
                // left alone and daydreams of money things while "Ten chats" is on.
                .creatureAmbience(CreatureAmbience(dozesAfter: AssistantMetrics.dozesAfter,
                                                   daydreams: chatterOn ? AssistantChatter.daydreams : []))
                .frame(width: AssistantMetrics.heroMascot, height: AssistantMetrics.heroMascot)
                // Room over Ten for its words.
                .padding(.top, AssistantMetrics.speechRoom)
                .simultaneousGesture(TapGesture().onEnded { tappedTen() })
                // A moment after the screen settles, and once the chats are known.
                .task {
                    try? await Task.sleep(for: AssistantMetrics.greetingDelay)
                    greet()
                }
            VStack(spacing: AppSpacing.sm) {
                Text(String(localized: "assistant.greeting.title"))
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.Text.primary)
                Text(String(localized: "assistant.greeting.message"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.Text.secondary)
                // Voice and import moved here from "+": say where they are.
                Text(String(localized: "assistant.greeting.tools"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.tertiary)
            }
            .multilineTextAlignment(.center)
            SuggestionChips(topicQuestions.isEmpty ? Self.presets : topicQuestions, systemImage: "sparkles", layout: .wrap) {
                start(.question($0, spoken: false))
            }
            if !chats.isEmpty {
                recentChats
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ten's lines

    private func play(_ next: CreatureGesture) {
        gesture = next
        gestureCount += 1
    }

    /// Once a day: the greeting for the hour and a wave, or, while there are no chats, a hint
    /// pointing at the ready-made questions under Ten.
    private func greet() {
        let today = AssistantChatter.dayKey(.now)
        guard greetedDay != today else { return }
        greetedDay = today
        if chats.isEmpty {
            speech = AssistantChatter.askMe
            play(.point(.down))
        } else {
            let (line, wave) = AssistantChatter.greeting(at: .now)
            speech = line
            if let wave { play(wave) }
        }
    }

    /// A line about every other tap, two seconds apart at least; three quick taps make Ten dizzy.
    private func tappedTen() {
        let now = Date.now
        taps = taps.filter { now.timeIntervalSince($0) < AssistantChatter.dizzyWindow } + [now]
        if taps.count >= 3 {
            taps = []
            tapLineTurn += 1
            speech = AssistantChatter.dizzy(tapLineTurn)
            lastTapLine = now
            return
        }
        tapCount += 1
        guard tapCount.isMultiple(of: 2), now.timeIntervalSince(lastTapLine) >= AssistantChatter.tapLineGap else { return }
        lastTapLine = now
        speech = AssistantChatter.tapLine(tapLineTurn)
        tapLineTurn += 1
    }

    /// The chat open last, then the other latest chats.
    private var chats: [AgentThreadSummary] {
        let current = model.currentThread
        return [current].compactMap { $0 } + model.recentThreads.filter { $0.id != current?.id }
    }

    /// The latest chats; a tap opens one, a long press deletes it.
    private var recentChats: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "assistant.recent"))
            VStack(spacing: AppSpacing.md) {
                ForEach(chats) { thread in
                    Button {
                        Task {
                            if await model.open(threadId: thread.id) { showChat() }
                        }
                    } label: {
                        ItemRow(
                            thread.title,
                            meta: [MetaLine([.text(thread.updatedAt.formatted(.relative(presentation: .named)))])],
                            leading: .symbol("bubble.left.and.text.bubble.right"),
                            titleLineLimit: 1
                        ) {
                            DisclosureChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await model.deleteThread(thread.id) }
                        } label: {
                            Label(String(localized: "assistant.recent.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .cardContentPadding()
            .cardStyle()
            .animation(AppAnimation.smooth, value: chats.map(\.id))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Behaviour

    /// The open chat as the only page over the home.
    private func showChat() {
        var chat = NavigationPath()
        chat.append(AssistantPage.chat)
        path = chat
    }

    /// Starts a new chat with a question or a message Ten wrote. A plain record is drafted on
    /// the phone and needs no consent (FastPath); anything else waits for the cloud mode. While
    /// a chat is still answering, it is shown instead.
    private func start(_ start: Start) {
        guard !model.isWorking else {
            showChat()
            return
        }
        switch start {
        case .question(let raw, let spoken):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            model.reset()
            topicQuestions = []
            if hasConsent {
                draft = ""
                showChat()
                Task { await model.send(text, spoken: spoken, cloudAllowed: true) }
            } else {
                Task {
                    if await model.send(text, spoken: spoken, cloudAllowed: false) {
                        draft = ""
                        showChat()
                    } else {
                        awaitingConsent = start
                        showingConsent = true
                    }
                }
            }
        case .notice(let notice):
            guard hasConsent else {
                awaitingConsent = start
                showingConsent = true
                return
            }
            model.reset()
            AssistantInbox.shared.markRead(notice.id)
            showChat()
            Task { await model.ask(about: notice) }
        }
    }

    private static var presets: [String] {
        [
            String(localized: "assistant.preset.month"),
            String(localized: "assistant.preset.allowance"),
            String(localized: "assistant.preset.compare"),
            String(localized: "assistant.preset.budgets"),
            String(localized: "assistant.preset.subscriptions"),
            String(localized: "assistant.preset.save"),
            String(localized: "assistant.preset.invest"),
        ]
    }
}

enum AssistantMetrics {
    /// The greeting's mascot.
    static let heroMascot: CGFloat = 220
    /// The room over the greeting's mascot for its words (DesignKit 4.10): a line of two rises
    /// about this far over Ten's square.
    static let speechRoom: CGFloat = 48
    /// How long the home waits before Ten greets.
    static let greetingDelay: Duration = .seconds(0.8)
    /// Seconds left alone on the home before Ten dozes off (a tap wakes it).
    static let dozesAfter: Double = 45
    /// Words beside Ten in a chat: from the middle of the navigation bar to the screen's edge.
    static let chatSpeechWidth: CGFloat = 150
    /// The mascot on a message Ten wrote (AssistantNoticeCard).
    static let headerMascot: CGFloat = AppIconSize.xl
    /// Ten in a chat, in the middle of the navigation bar (the owner's size).
    static let chatMascot: CGFloat = 120
    /// How far Ten rises into the navigation bar (its inline height); the rest hangs over the
    /// top of the thread.
    static let chatMascotLift: CGFloat = 44
    /// How far Ten's bar reaches below it, so the thread is blurred under all of Ten and
    /// clears only past it.
    static let chatMascotTail: CGFloat = AppSpacing.xxl
    /// The longest question: plenty for a person, short enough to keep the turn cheap.
    static let questionLimit = 1000
    /// The free answers left from which the composer shows the count.
    static let allowanceHint = 3
    /// The person agreed to the cloud mode (the consent sheet's "Turn on").
    static let consentKey = "assistant.cloudConsent.v1"

    /// What Ten shows: thinking while the assistant runs tools, answering while it writes the
    /// reply, the reply's mood after, confused or sad when a question was not answered.
    static func mood(for model: AssistantViewModel) -> ParticleCreature.Mood {
        switch model.phase {
        case .working:
            return model.streamingReply.isEmpty ? .thinking : .answering
        case .failed(let failure):
            return failure == .offline ? .sad : .confused
        case .idle:
            switch model.replyMood {
            case .happy: return .happy
            case .concerned: return .worried
            case .celebrate: return .celebrating
            case .idle: return .idle
            }
        }
    }
}
