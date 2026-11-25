//
//  AgentReplyReport.swift
//  Tenra
//
//  "Не то" under one of Ten's answers (docs/domains/assistant.md §7): the person tells the owner
//  what was wrong with it and, by sending, passes on that exchange: their question and Ten's
//  words. The cards beside the words go only as their kinds ("metric", "confirm"): their figures,
//  labels and the drafts' contents stay on the phone. The sheet shows exactly what goes before it
//  is sent (AssistantReplyReportSheet); it travels as feedback (`POST /v1/feedback`, source
//  `reply`), kept for the owner like any message about the app.
//

import Foundation

nonisolated enum AgentReplyReport {
    /// The server's limits (server/assistant/src/feedback.ts, FEEDBACK_LIMITS).
    static let questionLimit = 2000
    static let answerLimit = 4000
    static let commentLimit = 2000

    /// The exchange as it is sent: the question, Ten's words in the order shown, and the kinds of
    /// the other blocks, each once.
    static func exchange(question: String, reply: AgentReply) -> AgentFeedbackMessage.Exchange {
        var words: [String] = []
        var cards: [String] = []
        for block in reply.blocks {
            if case .text(let text) = block {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { words.append(trimmed) }
            } else if let kind = kind(of: block), !cards.contains(kind) {
                cards.append(kind)
            }
        }
        return AgentFeedbackMessage.Exchange(
            question: String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(questionLimit)),
            answer: String(words.joined(separator: "\n\n").prefix(answerLimit)),
            cards: cards
        )
    }

    /// The message to the owner: the person's words, or the reason they picked when they wrote
    /// none (the server wants words).
    static func message(
        reason: AgentFeedbackMessage.ReplyReason,
        comment: String,
        exchange: AgentFeedbackMessage.Exchange
    ) -> AgentFeedbackMessage {
        let typed = String(comment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(commentLimit))
        return AgentFeedbackMessage(
            text: typed.isEmpty ? title(of: reason) : typed,
            mood: .bad,
            source: .reply,
            reason: reason,
            exchange: exchange
        )
    }

    /// A reason's words on its chip.
    static func title(of reason: AgentFeedbackMessage.ReplyReason) -> String {
        switch reason {
        case .wrong: String(localized: "assistant.report.reason.wrong")
        case .misunderstood: String(localized: "assistant.report.reason.misunderstood")
        case .notDone: String(localized: "assistant.report.reason.notDone")
        case .other: String(localized: "assistant.report.reason.other")
        }
    }

    /// A card's kind, as the server keeps it (`^[a-z_]{1,24}$`); nil for words.
    static func kind(of block: AgentBlock) -> String? {
        switch block {
        case .text: nil
        case .metric: "metric"
        case .chart: "chart"
        case .transactions: "transactions"
        case .budgets: "budgets"
        case .recurring: "recurring"
        case .forecast: "forecast"
        case .insight: "insight"
        case .confirm: "confirm"
        case .open: "open"
        case .create: "create"
        case .unsupported: "unsupported"
        }
    }
}
