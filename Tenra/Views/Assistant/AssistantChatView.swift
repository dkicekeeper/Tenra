//
//  AssistantChatView.swift
//  Tenra
//
//  One chat with the assistant, pushed from its home (AssistantView) as a page of its own
//  (docs/plan-ai-assistant.md §3.3, §3.6): the person's questions in bubbles, the replies as the
//  app's own cards, the step the assistant is on while it works, its suggestions for what to
//  ask next, and the field. The navigation bar holds only the way back to the home and Ten in
//  the middle, 120 pt (the owner's size): it rises into the bar and hangs over the top of the
//  thread, with no backing of its own, drawn over the content that scrolls under it. The tab
//  bar steps aside (TabBarVisibility), so the chat has the screen.
//
//  Ten shows what is going on: thinking while it runs tools, answering while it writes, the
//  reply's mood after, confused or sad when a question could not be answered. The reply's text
//  streams in as the model writes it (AssistantStreamingReply) and can be selected and copied.
//
//  Sending a question scrolls it to the top of the screen, and its turn is at least a screen
//  tall, so a long reply is read from its start. A tap on the thread puts the keyboard away.
//
//  Without Pro, a line over the field counts the free answers once 3 or fewer are left
//  (docs/plan-ai-assistant.md §6) and opens the paywall; a question over the allowance waits in
//  the thread with the Pro button and goes once Pro is on. The paperclip attaches a receipt or
//  a statement to this chat, the microphone dictates the next message.
//

import SwiftUI

struct AssistantChatView: View {
    let model: AssistantViewModel

    @Environment(PremiumManager.self) private var premium
    /// Optional so a preview without the tab bar's owner does not trap.
    @Environment(TabBarVisibility.self) private var tabBarVisibility: TabBarVisibility?
    @State private var draft = ""
    @State private var showingVoice = false
    @State private var attachmentSource: AssistantAttachmentSource?
    @State private var readingAttachment = false
    @State private var attachmentError: String?
    @State private var showingPaywall = false
    @State private var showingConsent = false
    @State private var questionAwaitingConsent: String?
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @FocusState private var composerFocused: Bool
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    /// The thread's visible height, which the latest turn fills at least.
    @State private var viewportHeight: CGFloat = 0
    // Ten's thoughts and reactions (AssistantChatter).
    @AppStorage(AssistantChatter.enabledKey) private var chatterOn = true
    @State private var speech: CreatureSpeech?
    @State private var gesture: CreatureGesture = .nod
    @State private var gestureCount = 0
    @State private var thoughtTurn = 0

    var body: some View {
        ZStack(alignment: .top) {
            thread
            // Ten in the middle of the navigation bar, hanging over the top of the thread: over
            // the content that scrolls under it, never under it, and taking no room of its own.
            // Its bubble goes beside it, on the free side of the bar (VoiceOver reads it; Ten
            // itself is hidden from VoiceOver by ParticleCreature).
            ParticleCreature(mood: mascotMood, speech: chatterOn ? speech : nil)
                .creatureGesture(gesture, trigger: gestureCount)
                .frame(width: AssistantMetrics.chatMascot, height: AssistantMetrics.chatMascot)
                .offset(y: -AssistantMetrics.chatMascotLift)
                .allowsHitTesting(false)
        }
        .task(id: model.isWorking) { await thinkWhileWorking() }
        .onChange(of: model.phase) { old, new in react(from: old, to: new) }
        .navigationBarTitleDisplayMode(.inline)
        // The chat has the screen: the tab bar steps aside while it is open (the stable owner
        // restores it, as for TransactionAddModal).
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            tabBarVisibility?.isHidden = true
            model.refreshAllowance()
        }
        .onDisappear { tabBarVisibility?.isHidden = false }
        .onChange(of: premium.isPro) { model.refreshAllowance() }
        .paywallSheet(isPresented: $showingPaywall) {
            model.refreshAllowance()
            Task { await model.retry() }
        }
        .sheet(isPresented: $showingVoice) {
            AssistantVoiceSheet { send($0, spoken: true) }
        }
        .assistantConsent(
            isPresented: $showingConsent,
            onAllow: {
                if let question = questionAwaitingConsent {
                    questionAwaitingConsent = nil
                    send(question)
                }
            },
            onDecline: { questionAwaitingConsent = nil }
        )
    }

    /// The questions and replies, with the field floating at the bottom. At rest the thread
    /// starts under Ten; scrolled, it passes beneath.
    private var thread: some View {
        ScrollView {
            // A plain stack: a lazy one guessed the heights of replies it had not drawn, and
            // a long reply scrolled the thread into empty space.
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
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
        // The part of Ten below the navigation bar: the thread starts under it.
        .safeAreaPadding(.top, AssistantMetrics.chatMascot - AssistantMetrics.chatMascotLift)
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
                onSend: { send(draft) }
            )
        }
        .assistantAttachmentSources(
            source: $attachmentSource,
            reading: $readingAttachment,
            takesHandedOverFiles: false,
            onRead: { attachment, summary in
                HapticManager.success()
                model.attach(attachment, summary: summary)
            },
            onFailure: { message in
                HapticManager.error()
                attachmentError = message
            }
        )
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
        if !model.suggestions.isEmpty {
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

    /// Sends the next message. A plain record is drafted on the phone and needs no consent
    /// (FastPath); anything else waits for the cloud mode to be turned on.
    private func send(_ text: String, spoken: Bool = false) {
        guard !model.isWorking, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if hasConsent { draft = "" }
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
        AssistantMetrics.mood(for: model)
    }

    // MARK: - Ten's thoughts and reactions

    private func play(_ next: CreatureGesture) {
        gesture = next
        gestureCount += 1
    }

    /// A thought once Ten has worked a moment; gone when the work ends.
    private func thinkWhileWorking() async {
        guard model.isWorking else {
            if speech?.style == .think { speech = nil }
            return
        }
        try? await Task.sleep(for: AssistantChatter.thoughtDelay)
        guard !Task.isCancelled, model.isWorking else { return }
        speech = AssistantChatter.thought(thoughtTurn)
        thoughtTurn += 1
    }

    /// When the work ends: a nod for a reply, a cheer for a celebrated one, a word for a
    /// question that was not answered.
    private func react(from old: AssistantViewModel.Phase, to new: AssistantViewModel.Phase) {
        guard case .working = old else { return }
        switch new {
        case .idle:
            if model.replyMood == .celebrate {
                speech = AssistantChatter.cheer
                play(.hop)
            } else {
                if speech?.style == .think { speech = nil }
                play(.nod)
            }
        case .failed(let failure):
            let (line, reaction) = AssistantChatter.reaction(to: failure)
            speech = line
            play(reaction)
        case .working:
            break
        }
    }
}
