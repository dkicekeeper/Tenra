//
//  AssistantChatView.swift
//  Tenra
//
//  One chat with the assistant, pushed from its home (AssistantView) as a page of its own
//  (docs/plan-ai-assistant.md §3.3, §3.6): the person's questions in bubbles, the replies as the
//  app's own cards, the step the assistant is on while it works, its suggestions for what to
//  ask next, and the field. The navigation bar holds only the way back to the home and Ten in
//  the middle, 120 pt (the owner's size): it rises into the bar and hangs over the top of the
//  thread, with no backing of its own. The thread scrolls under it and fades out softly as it
//  goes (a mask: gone under Ten's upper half, back by its lower edge), so the text never runs
//  through the particles. The tab bar steps aside (TabBarVisibility), so the chat has the
//  screen.
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
    /// Ten's lower edge in the window, where the thread is back in full.
    @State private var mascotBottom: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            thread
            // Ten in the middle of the navigation bar, hanging over the top of the thread: over
            // the content that scrolls under it, never under it, and taking no room of its own.
            ParticleCreature(mood: mascotMood)
                .frame(width: AssistantMetrics.chatMascot, height: AssistantMetrics.chatMascot)
                .padding(.top, -AssistantMetrics.chatMascotLift)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { mascotBottom = $0 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
        // Scrolled up, the thread fades out under Ten instead of running through it. The field
        // stays outside the mask: its glass sees the page as it is.
        .mask { threadFade }
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

    /// The thread's mask: clear under the navigation bar and Ten's upper half, fading in over
    /// its lower half, whole from its lower edge down. Placed in the window's coordinates, so it
    /// lines up with Ten wherever the scroll view's own frame starts.
    private var threadFade: some View {
        GeometryReader { proxy in
            let hidden = max(0, mascotBottom - AssistantMetrics.chatMascotFade - proxy.frame(in: .global).minY)
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: hidden)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: AssistantMetrics.chatMascotFade)
                Rectangle()
            }
        }
        .ignoresSafeArea()
    }

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
}
