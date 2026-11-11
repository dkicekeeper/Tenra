//
//  FeedbackSheet.swift
//  Tenra
//
//  "Write to Ten": what the person thinks of Tenra, in their own words, for the owner to read
//  (docs/domains/assistant.md §6, "Feedback"). The message goes to the server's
//  `POST /v1/feedback` with the app's version, the system's and the language; no name, no
//  records, and no model reads it. Opened from Ten's message on Home and from the "not really"
//  answer of the rating survey.
//
//  The transport is passed in, not read from the environment, so the sheet opens wherever its
//  presenter has one.
//

import SwiftUI

struct FeedbackSheet: View {
    let source: AgentFeedbackMessage.Source
    let transport: AgentFeedbackTransport
    /// Called once the server took the message.
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mood: AgentFeedbackMessage.Mood?
    @State private var phase: Phase = .writing
    @FocusState private var writing: Bool

    private enum Phase: Equatable {
        case writing, sending, sent, failed
    }

    init(source: AgentFeedbackMessage.Source, transport: AgentFeedbackTransport, onSent: @escaping () -> Void = {}) {
        self.source = source
        self.transport = transport
        self.onSent = onSent
        // Someone who answered "not really" to the survey came here with a complaint.
        _mood = State(initialValue: source == .survey ? .bad : nil)
    }

    private var message: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if phase == .sent {
                    EmptyState(
                        icon: "checkmark.circle",
                        title: String(localized: "feedback.sent.title"),
                        description: String(localized: "feedback.sent.message")
                    )
                } else {
                    form
                }
            }
            .navigationTitle(String(localized: "feedback.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "button.close"))
                }
                if phase != .sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "paperplane")
                        }
                        .dsButton()
                        .disabled(message.isEmpty || phase == .sending)
                        .accessibilityLabel(String(localized: "feedback.send"))
                    }
                }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(String(localized: "feedback.intro"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                Picker(String(localized: "feedback.title"), selection: $mood) {
                    Text(String(localized: "feedback.mood.good")).tag(AgentFeedbackMessage.Mood?.some(.good))
                    Text(String(localized: "feedback.mood.bad")).tag(AgentFeedbackMessage.Mood?.some(.bad))
                }
                .pickerStyle(.segmented)
                FormSection {
                    TextField(String(localized: "feedback.placeholder"), text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .font(AppTypography.body)
                        .padding(.vertical, AppSpacing.md)
                        .focused($writing)
                }
                if phase == .failed {
                    Text(String(localized: "feedback.error"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textPrimary)
                }
                Text(String(localized: "feedback.privacy"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { writing = true }
    }

    private func send() {
        let sending = AgentFeedbackMessage(text: message, mood: mood, source: source)
        guard !sending.text.isEmpty, phase != .sending else { return }
        phase = .sending
        Task {
            do {
                try await transport.feedback(sending)
                phase = .sent
                onSent()
                // Someone who likes Tenra and has just said so is the one to ask for a rating;
                // Apple decides whether its prompt shows.
                if sending.mood == .good, source != .survey {
                    RatingPromptService.shared.requestNativeReview()
                }
            } catch {
                phase = .failed
            }
        }
    }
}
