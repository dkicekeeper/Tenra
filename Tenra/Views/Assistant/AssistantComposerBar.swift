//
//  AssistantComposerBar.swift
//  Tenra
//
//  The field at the bottom of the assistant's home and of a chat: in a chat, the questions Ten
//  suggests after its reply, one row that scrolls sideways edge to edge; how many free answers
//  are left (without Pro, from 3), a line when an attachment could not be read, and the
//  composer with the paperclip's attach menu and the microphone (AssistantAttachmentMenu,
//  AssistantVoiceSheet). What sending does is the page's own: the home starts a new chat, a
//  chat goes on.
//

import SwiftUI

struct AssistantComposerBar: View {
    let model: AssistantViewModel
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    let readingAttachment: Bool
    let attachmentError: String?
    let onAttach: (AssistantAttachmentSource) -> Void
    let onVoice: () -> Void
    let onPaywall: () -> Void
    let onSend: () -> Void
    /// The questions Ten suggests next (a chat); empty while it works.
    var suggestions: [String] = []
    var onSuggestion: (String) -> Void = { _ in }

    @Environment(PremiumManager.self) private var premium

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            if !suggestions.isEmpty {
                // Edge to edge: the first chip starts at the screen's padding and the row scrolls
                // past it.
                SuggestionChips(suggestions, inset: AppSpacing.lg) { onSuggestion($0) }
                    .transition(.opacity)
            }
            VStack(spacing: AppSpacing.xs) {
                if let allowance = model.allowance, allowance.remaining <= AssistantMetrics.allowanceHint, !premium.isPro {
                    allowanceLine(allowance)
                        .transition(.opacity)
                }
                // An attachment that could not be read shows in the field's own error slot
                // (over the field, shared with the character count).
                MessageComposer(
                    text: $draft,
                    placeholder: String(localized: "assistant.composer.placeholder"),
                    isSending: model.isWorking,
                    errorMessage: attachmentError,
                    limit: AssistantMetrics.questionLimit,
                    focus: focus,
                    leading: {
                        AssistantAttachmentMenu { source in
                            HapticManager.light()
                            onAttach(source)
                        }
                        .disabled(readingAttachment)
                    },
                    onVoice: onVoice
                ) {
                    onSend()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("assistant.composer")
                // Send, attach and the microphone sit by the field: a tap on them keeps the keyboard.
                .keepsKeyboardOnTap()
            }
            .screenPadding()
        }
        .padding(.bottom, AppSpacing.sm)
        .animation(AppAnimation.smooth, value: suggestions)
        .animation(AppAnimation.smooth, value: model.allowance)
        .animation(AppAnimation.smooth, value: attachmentError)
    }

    /// "2 free answers left", or when the next ones come; a tap opens the paywall.
    private func allowanceLine(_ allowance: AssistantAllowance.Status) -> some View {
        DSButton(Self.allowanceText(allowance), systemImage: "sparkles", appearance: .flat, role: .neutral, size: .small) {
            onPaywall()
        }
        .accessibilityHint(String(localized: "settings.pro.cta.title"))
    }

    static func allowanceText(_ allowance: AssistantAllowance.Status) -> String {
        if allowance.remaining > 0 {
            return String(format: NSLocalizedString("assistant.allowance.remaining", comment: "Free answers left"), allowance.remaining)
        }
        guard let renewsAt = allowance.renewsAt else { return String(localized: "assistant.error.freeLimit") }
        return String(format: String(localized: "assistant.allowance.renews"), renewsAt.formatted(.dateTime.day().month(.wide)))
    }
}

extension View {
    /// The cloud consent (App Review 5.1.2(i)): asked before the first question goes to the
    /// cloud; "Turn on" stores it and runs `onAllow`.
    func assistantConsent(isPresented: Binding<Bool>, onAllow: @escaping () -> Void, onDecline: @escaping () -> Void) -> some View {
        modifier(AssistantConsentSheet(isPresented: isPresented, onAllow: onAllow, onDecline: onDecline))
    }
}

private struct AssistantConsentSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onAllow: () -> Void
    let onDecline: () -> Void

    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            PromptSheet(
                systemImage: "lock.shield",
                title: String(localized: "assistant.consent.title"),
                message: String(localized: "assistant.consent.message"),
                primaryTitle: String(localized: "assistant.consent.allow"),
                secondaryTitle: String(localized: "assistant.consent.notNow"),
                detent: .large,
                onPrimary: {
                    hasConsent = true
                    onAllow()
                },
                onSecondary: onDecline
            )
        }
    }
}
