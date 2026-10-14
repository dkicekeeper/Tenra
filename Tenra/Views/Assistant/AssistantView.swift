//
//  AssistantView.swift
//  Tenra
//
//  The assistant's chat (docs/plan-ai-assistant.md §1, §3.3, §3.6). Empty, it greets with the
//  mascot and a few ready-made questions; then the thread: the person's questions in bubbles,
//  the replies as the app's own cards, the step the assistant is on while it works, its
//  suggestions for what to ask next. The composer floats over the content at the bottom.
//
//  The mascot shows what is going on: thinking while it works, the reply's mood after, confused
//  or sad when a question could not be answered. In a thread it stands over the thread, under
//  the navigation bar, in a band of its own that the content never scrolls into (120 pt, 64 pt
//  while the person types), so Ten stays in sight; the reply's text streams in as the model
//  writes it (AssistantStreamingReply).
//
//  Sending a question scrolls it to the top of the screen, and its turn is at least a screen
//  tall, so a long reply is read from its start. A tap on the thread puts the keyboard away. The
//  latest chats (AgentThreadStore) are under the greeting and in the history menu.
//
//  Opened from a screen's "Ask Ten" (AssistantEntryPoints), it offers questions about that
//  account, category, insight or the history in place of its general ones, until one goes.
//  Opened from "Go through it" on a message Ten wrote (on Home, AssistantNoticesSection), it
//  asks that message's question.
//
//  Nothing leaves the phone before the person agrees: the first question opens the consent
//  sheet (App Review 5.1.2(i)), and goes once they turn the cloud mode on.
//
//  Without Pro, a line over the composer counts the free answers once 3 or fewer are left
//  (docs/plan-ai-assistant.md §6), and opens the paywall. A question over the allowance waits
//  in the thread with the Pro button and goes once Pro is on.
//
//  The composer carries what used to sit behind "+" (§3.8): the paperclip's menu attaches a
//  receipt (scanner or photos) or a statement (PDF, or CSV into its own import flow), read on
//  the phone into a summary card (AssistantAttachmentSources, AssistantAttachmentCard); the
//  microphone (while the field is empty) opens the voice sheet, whose words go as a message
//  (AssistantVoiceSheet).
//

import SwiftUI

struct AssistantView: View {
    let model: AssistantViewModel
    /// Closes the screen the assistant is presented in; nil shows no close button.
    var onClose: (() -> Void)?

    @Environment(PremiumManager.self) private var premium
    @Environment(AppCoordinator.self) private var coordinator
    @State private var draft = ""
    @State private var showingVoice = false
    @State private var attachmentSource: AssistantAttachmentSource?
    @State private var readingAttachment = false
    @State private var attachmentError: String?
    /// Questions about the screen the assistant was opened from.
    @State private var topicQuestions: [String] = []
    @State private var showingPaywall = false
    @State private var showingConsent = false
    @State private var questionAwaitingConsent: String?
    @State private var noticeAwaitingConsent: AssistantNotice?
    private let inbox = AssistantInbox.shared
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @FocusState private var composerFocused: Bool
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    /// The thread's visible height, which the latest turn fills at least.
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if !model.entries.isEmpty {
                threadMascot
                    // Over the thread where they meet: a particle that drifts out of the band
                    // is drawn over the content, never under it.
                    .zIndex(1)
                    .transition(.opacity)
            }
            thread
        }
        .animation(AppAnimation.contentSpring, value: model.entries.isEmpty)
        .assistantAttachmentSources(
            source: $attachmentSource,
            reading: $readingAttachment,
            onRead: { attachment, summary in
                HapticManager.success()
                model.attach(attachment, summary: summary)
            },
            onFailure: { message in
                HapticManager.error()
                attachmentError = message
            }
        )
        .navigationTitle(model.entries.isEmpty ? String(localized: "tab.assistant") : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AssistantRoute.self) { route in
            AssistantDestinationView(route: route)
        }
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "button.close"), systemImage: "xmark") {
                        onClose()
                    }
                }
            }
            if !model.recentThreads.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    historyMenu
                }
            }
            if !model.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.reset()
                    } label: {
                        Label(String(localized: "assistant.newChat"), systemImage: "square.and.pencil")
                    }
                    .disabled(model.isWorking)
                }
            }
        }
        .paywallSheet(isPresented: $showingPaywall) {
            model.refreshAllowance()
            Task { await model.retry() }
        }
        .sheet(isPresented: $showingVoice) {
            AssistantVoiceSheet { send($0, spoken: true) }
        }
        .onAppear {
            model.refreshAllowance()
        }
        .onChange(of: coordinator.assistantTopic, initial: true) { _, topic in
            guard topic != nil, let topic = coordinator.consumeAssistantTopic() else { return }
            topicQuestions = topic.questions
        }
        // "Go through it" on Home.
        .onChange(of: coordinator.pendingNotice, initial: true) { _, notice in
            guard notice != nil, let notice = coordinator.consumePendingNotice() else { return }
            goThrough(notice)
        }
        .task { await model.restore() }
        .onChange(of: premium.isPro) { model.refreshAllowance() }
        .sheet(isPresented: $showingConsent) {
            PromptSheet(
                systemImage: "lock.shield",
                title: String(localized: "assistant.consent.title"),
                message: String(localized: "assistant.consent.message"),
                primaryTitle: String(localized: "assistant.consent.allow"),
                secondaryTitle: String(localized: "assistant.consent.notNow"),
                detent: .large,
                onPrimary: {
                    hasConsent = true
                    if let question = questionAwaitingConsent {
                        questionAwaitingConsent = nil
                        send(question)
                    }
                    if let notice = noticeAwaitingConsent {
                        noticeAwaitingConsent = nil
                        goThrough(notice)
                    }
                },
                onSecondary: {
                    questionAwaitingConsent = nil
                    noticeAwaitingConsent = nil
                }
            )
        }
    }

    /// Ten over the thread, in a band of its own: the content scrolls under the band's edge and
    /// never over Ten. Smaller while the person types, to leave the thread room over the
    /// keyboard.
    private var threadMascot: some View {
        let size = composerFocused ? AssistantMetrics.typingMascot : AssistantMetrics.threadMascot
        return ParticleCreature(mood: mascotMood)
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
            // At full size its empty top edge tucks under the navigation bar.
            .padding(.top, composerFocused ? 0 : -AppSpacing.xl)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(AppAnimation.contentSpring, value: composerFocused)
    }

    /// The questions and replies, with the composer floating at the bottom.
    private var thread: some View {
        ScrollView {
            // A plain stack: a lazy one guessed the heights of replies it had not drawn, and
            // a long reply scrolled the thread into empty space.
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if model.entries.isEmpty {
                    greeting
                }
                ForEach(earlierEntries) { entry in
                    entryView(entry)
                        .id(entry.id)
                }
                // The latest question and everything after it, at least a screen tall: sending
                // a question scrolls it to the top, and the reply is read from its start.
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    ForEach(currentTurn) { entry in
                        entryView(entry)
                            .id(entry.id)
                    }
                    turnFooter
                }
                .frame(minHeight: currentTurn.isEmpty ? 0 : viewportHeight, alignment: .top)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .animation(AppAnimation.smooth, value: model.entries.count)
            .animation(AppAnimation.smooth, value: model.isWorking)
            .animation(AppAnimation.smooth, value: readingAttachment)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            viewportHeight = max(0, height - AppSpacing.lg)
        }
        .onChange(of: model.entries.last?.id) { _, _ in
            scrollToCurrentTurn()
        }
        .scrollDismissesKeyboard(.interactively)
        // A tap anywhere on the thread puts the keyboard away (buttons still work).
        .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: AppSpacing.xs) {
                if let allowance = model.allowance, allowance.remaining <= AssistantMetrics.allowanceHint, !premium.isPro {
                    allowanceLine(allowance)
                        .transition(.opacity)
                }
                if let attachmentError {
                    InlineStatusText(message: attachmentError, type: .error)
                        .transition(.opacity)
                }
                MessageComposer(
                    text: $draft,
                    placeholder: String(localized: "assistant.composer.placeholder"),
                    isSending: model.isWorking,
                    limit: AssistantMetrics.questionLimit,
                    focus: $composerFocused,
                    leading: {
                        AssistantAttachmentMenu { source in
                            HapticManager.light()
                            attachmentError = nil
                            attachmentSource = source
                        }
                        .disabled(readingAttachment)
                    },
                    onVoice: { showingVoice = true }
                ) {
                    send(draft)
                }
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.sm)
            .animation(AppAnimation.smooth, value: model.allowance)
            .animation(AppAnimation.smooth, value: attachmentError)
        }
    }

    // MARK: - Thread

    /// Where the latest turn starts: the last question or attachment.
    private var currentTurnStart: Int {
        model.entries.lastIndex { entry in
            switch entry.content {
            case .question, .attachment: true
            case .reply: false
            }
        } ?? model.entries.count
    }

    private var earlierEntries: ArraySlice<AssistantViewModel.Entry> {
        model.entries[..<currentTurnStart]
    }

    private var currentTurn: ArraySlice<AssistantViewModel.Entry> {
        model.entries[currentTurnStart...]
    }

    /// Under the latest turn: what the assistant is doing or writing, the Pro offer, the next
    /// questions.
    @ViewBuilder
    private var turnFooter: some View {
        if model.isWorking, !model.streamingReply.isEmpty {
            AssistantStreamingReply(texts: model.streamingReply)
        } else if case .working(let step) = model.phase {
            workingRow(step.title)
                .transition(.opacity)
        } else if readingAttachment {
            workingRow(String(localized: "assistant.attachment.reading"))
                .transition(.opacity)
        }
        if case .failed(let failure) = model.phase,
           failure == .proRequired || failure == .limitReached || failure == .freeLimit, !premium.isPro {
            DSButton(String(localized: "settings.pro.cta.title"), systemImage: "sparkles") {
                showingPaywall = true
            }
        }
        if !model.entries.isEmpty, !topicQuestions.isEmpty, !model.isWorking {
            SuggestionChips(topicQuestions, systemImage: "sparkles", layout: .wrap) { send($0) }
                .transition(.opacity)
        } else if !model.suggestions.isEmpty {
            SuggestionChips(model.suggestions) { send($0) }
                .transition(.opacity)
        }
    }

    /// The latest question at the top of the screen.
    private func scrollToCurrentTurn() {
        guard let first = currentTurn.first else { return }
        withAnimation(AppAnimation.smooth) {
            scrollPosition.scrollTo(id: first.id, anchor: .top)
        }
    }

    // MARK: - Pieces

    private var greeting: some View {
        VStack(spacing: AppSpacing.lg) {
            ParticleCreature(mood: mascotMood, isInteractive: true)
                .frame(width: AssistantMetrics.heroMascot, height: AssistantMetrics.heroMascot)
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
            SuggestionChips(topicQuestions.isEmpty ? Self.presets : topicQuestions, systemImage: "sparkles", layout: .wrap) { send($0) }
            if !model.recentThreads.isEmpty {
                recentChats
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Go through it" (from Home): the message's question, after the cloud consent when it is
    /// not given. The message is read once its question goes.
    private func goThrough(_ notice: AssistantNotice) {
        guard !model.isWorking else { return }
        guard hasConsent else {
            noticeAwaitingConsent = notice
            showingConsent = true
            return
        }
        inbox.markRead(notice.id)
        topicQuestions = []
        Task { await model.ask(about: notice) }
    }

    /// The latest chats under the greeting; a tap opens one.
    private var recentChats: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "assistant.recent"))
            VStack(spacing: AppSpacing.md) {
                ForEach(model.recentThreads) { thread in
                    Button {
                        Task { await model.open(threadId: thread.id) }
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
                }
            }
            .cardContentPadding()
            .cardStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The latest chats from inside a thread.
    private var historyMenu: some View {
        Menu {
            ForEach(model.recentThreads) { thread in
                Button {
                    Task { await model.open(threadId: thread.id) }
                } label: {
                    Text(thread.title)
                    Text(thread.updatedAt.formatted(.relative(presentation: .named)))
                }
            }
        } label: {
            Label(String(localized: "assistant.history"), systemImage: "clock.arrow.circlepath")
        }
        .disabled(model.isWorking)
    }

    @ViewBuilder
    private func entryView(_ entry: AssistantViewModel.Entry) -> some View {
        switch entry.content {
        case .question(let text):
            let failure: AssistantFailure? = if case .failed(let reason) = model.phase, model.failedEntry == entry.id { reason } else { nil }
            MessageBubble(
                text,
                failure: failure?.message,
                onRetry: failure?.canRetry == true ? { Task { await model.retry() } } : nil
            )
        case .reply(let reply, let results):
            AssistantReplyView(reply: reply, results: results, drafts: model.drafts)
        case .attachment(let summary):
            AssistantAttachmentCard(model: model, entryId: entry.id, summary: summary)
        }
    }

    /// "2 free answers left", or when the next ones come; a tap opens the paywall.
    private func allowanceLine(_ allowance: AssistantAllowance.Status) -> some View {
        Button {
            showingPaywall = true
        } label: {
            Label(Self.allowanceText(allowance), systemImage: "sparkles")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.Text.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "settings.pro.cta.title"))
    }

    static func allowanceText(_ allowance: AssistantAllowance.Status) -> String {
        if allowance.remaining > 0 {
            return String(format: NSLocalizedString("assistant.allowance.remaining", comment: "Free answers left"), allowance.remaining)
        }
        guard let renewsAt = allowance.renewsAt else { return String(localized: "assistant.error.freeLimit") }
        return String(format: String(localized: "assistant.allowance.renews"), renewsAt.formatted(.dateTime.day().month(.wide)))
    }

    /// The step the assistant is on; Ten over the thread thinks meanwhile.
    private func workingRow(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.Text.secondary)
            .thinkingShimmer(isActive: true)
            .contentTransition(.opacity)
            .animation(AppAnimation.smooth, value: title)
    }

    // MARK: - Behaviour

    /// Sends the message. A plain record is drafted on the phone and needs no consent (FastPath);
    /// anything else waits for the cloud mode to be turned on.
    private func send(_ text: String, spoken: Bool = false) {
        guard !model.isWorking, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if hasConsent { draft = "" }
        topicQuestions = []
        Task {
            if await model.send(text, spoken: spoken, cloudAllowed: hasConsent) {
                draft = ""
            } else if !hasConsent {
                questionAwaitingConsent = text
                showingConsent = true
            }
        }
    }

    private var mascotMood: ParticleCreature.Mood {
        switch model.phase {
        case .working:
            return .thinking
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
    /// The mascot on a message Ten wrote (AssistantNoticeCard).
    static let headerMascot: CGFloat = AppIconSize.xl
    /// The mascot over a thread, under the navigation bar (the owner's size).
    static let threadMascot: CGFloat = 120
    /// The mascot over a thread while the person types: the thread keeps room over the keyboard.
    static let typingMascot: CGFloat = 64
    /// The longest question: plenty for a person, short enough to keep the turn cheap.
    static let questionLimit = 1000
    /// The free answers left from which the composer shows the count.
    static let allowanceHint = 3
    /// The person agreed to the cloud mode (the consent sheet's "Turn on").
    static let consentKey = "assistant.cloudConsent.v1"
}
