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
//  or sad when a question could not be answered.
//
//  Nothing leaves the phone before the person agrees: the first question opens the consent
//  sheet (App Review 5.1.2(i)), and goes once they turn the cloud mode on.
//
//  Without Pro, a line over the composer counts the free answers once 3 or fewer are left
//  (docs/plan-ai-assistant.md §6), and opens the paywall. A question over the allowance waits
//  in the thread with the Pro button and goes once Pro is on.
//
//  The composer carries what used to sit behind "+" (§3.8): the paperclip opens the import of a
//  receipt or a statement, the microphone (while the field is empty) voice input, both the
//  app's own screens with their own Pro gates.
//

import SwiftUI

struct AssistantView: View {
    let model: AssistantViewModel
    /// Closes the screen the assistant is presented in; nil shows no close button.
    var onClose: (() -> Void)?

    @Environment(PremiumManager.self) private var premium
    @State private var draft = ""
    @State private var showingVoice = false
    @State private var showingImport = false
    @State private var showingPaywall = false
    @State private var showingConsent = false
    @State private var questionAwaitingConsent: String?
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                if model.entries.isEmpty {
                    greeting
                }
                ForEach(model.entries) { entry in
                    entryView(entry)
                }
                if case .working(let step) = model.phase {
                    workingRow(step)
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
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .animation(AppAnimation.smooth, value: model.entries.count)
            .animation(AppAnimation.smooth, value: model.isWorking)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: AppSpacing.xs) {
                if let allowance = model.allowance, allowance.remaining <= AssistantMetrics.allowanceHint, !premium.isPro {
                    allowanceLine(allowance)
                        .transition(.opacity)
                }
                MessageComposer(
                    text: $draft,
                    placeholder: String(localized: "assistant.composer.placeholder"),
                    isSending: model.isWorking,
                    limit: AssistantMetrics.questionLimit,
                    focus: $composerFocused,
                    leading: {
                        Button {
                            HapticManager.light()
                            showingImport = true
                        } label: {
                            MessageComposerAccessory(systemImage: "paperclip")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "assistant.attach"))
                    },
                    onVoice: { showingVoice = true }
                ) {
                    send(draft)
                }
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.sm)
            .animation(AppAnimation.smooth, value: model.allowance)
        }
        .navigationTitle(String(localized: "tab.assistant"))
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
            if !model.entries.isEmpty {
                ToolbarItem(placement: .principal) {
                    ParticleCreature(mood: mascotMood, style: .compact)
                        .frame(width: AssistantMetrics.headerMascot, height: AssistantMetrics.headerMascot)
                }
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
            VoiceTab()
        }
        .sheet(isPresented: $showingImport) {
            OCRTab()
        }
        .onAppear { model.refreshAllowance() }
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
                },
                onSecondary: { questionAwaitingConsent = nil }
            )
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
            SuggestionChips(Self.presets, systemImage: "sparkles", layout: .wrap) { send($0) }
        }
        .frame(maxWidth: .infinity)
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

    private func workingRow(_ step: AssistantStep) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ParticleCreature(mood: .thinking, style: .compact)
                .frame(width: AssistantMetrics.headerMascot, height: AssistantMetrics.headerMascot)
            Text(step.title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.Text.secondary)
                .thinkingShimmer(isActive: true)
                .contentTransition(.opacity)
                .animation(AppAnimation.smooth, value: step)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Behaviour

    private func send(_ text: String) {
        guard !model.isWorking, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard hasConsent else {
            questionAwaitingConsent = text
            showingConsent = true
            return
        }
        draft = ""
        Task { await model.send(text) }
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
    /// The mascot in the navigation bar and next to the working step.
    static let headerMascot: CGFloat = AppIconSize.xl
    /// The longest question: plenty for a person, short enough to keep the turn cheap.
    static let questionLimit = 1000
    /// The free answers left from which the composer shows the count.
    static let allowanceHint = 3
    /// The person agreed to the cloud mode (the consent sheet's "Turn on").
    static let consentKey = "assistant.cloudConsent.v1"
}
