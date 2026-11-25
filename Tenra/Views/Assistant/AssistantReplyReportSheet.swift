//
//  AssistantReplyReportSheet.swift
//  Tenra
//
//  "Не то" under one of Ten's answers (AgentReplyReport, docs/domains/assistant.md §7): what was
//  wrong, a few words if the person wants, and, before anything goes, exactly what the developer
//  gets: the question and Ten's words. The cards' figures stay on the phone.
//

import SwiftUI

struct AssistantReplyReportSheet: View {
    let exchange: AgentFeedbackMessage.Exchange
    let transport: AgentFeedbackTransport
    /// Sent: the chat marks the answer reported.
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: AgentFeedbackMessage.ReplyReason?
    @State private var comment = ""
    @State private var isSending = false
    @State private var failed = false

    var body: some View {
        EditSheetContainer(
            title: String(localized: "assistant.report.title"),
            saveTitle: String(localized: "assistant.report.send"),
            isSaveDisabled: reason == nil,
            isSaving: isSending,
            wrapInForm: false,
            onSave: send,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    ChipPicker(
                        options: AgentFeedbackMessage.ReplyReason.allCases,
                        selection: $reason,
                        label: AgentReplyReport.title(of:)
                    )
                    .screenPadding()

                    FormSection(footer: String(localized: "assistant.report.commentFooter")) {
                        FormTextField(
                            text: $comment,
                            placeholder: String(localized: "assistant.report.commentPlaceholder"),
                            style: .row,
                            limit: AgentReplyReport.commentLimit
                        )
                    }
                    .screenPadding()

                    FormSection(
                        header: String(localized: "assistant.report.sentHeader"),
                        footer: String(localized: "assistant.report.sentFooter")
                    ) {
                        sentText(String(localized: "assistant.report.question"), exchange.question)
                        if !exchange.answer.isEmpty {
                            sentText(String(localized: "assistant.report.answer"), exchange.answer)
                        }
                    }
                    .screenPadding()

                    if failed {
                        InlineStatusText(message: String(localized: "assistant.report.failed"), type: .error)
                            .screenPadding()
                    }
                }
                .padding(.vertical, AppSpacing.lg)
            }
        }
    }

    /// One part of what is sent, as the developer will read it.
    private func sentText(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(text)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.Text.primary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private func send() {
        guard let reason, !isSending else { return }
        isSending = true
        failed = false
        let message = AgentReplyReport.message(reason: reason, comment: comment, exchange: exchange)
        Task {
            do {
                try await transport.feedback(message)
                HapticManager.success()
                AccessibilityAnnouncer.announce(String(localized: "assistant.report.sent"))
                onSent()
                dismiss()
            } catch {
                isSending = false
                failed = true
            }
        }
    }
}
