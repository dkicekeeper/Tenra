//
//  AssistantViewModel.swift
//  Tenra
//
//  The assistant screen's state (docs/plan-ai-assistant.md §3.7): the visible thread of
//  questions and replies, what the assistant is doing right now (the step names the tool it
//  runs), and a failed question that can be retried. The conversation itself (history, tools,
//  the server loop) is `AgentConversation`; this type only turns it into screen state.
//
//  The <app_context> block goes with the first question and again whenever it changes (a new
//  day, an account or a category added), as the server's prompt expects.
//
//  What the person did on the confirm cards since the last reply (a draft saved, undone or
//  edited, with what an edited one holds now) goes with the next question as a <draft_status>
//  block, so the model knows what is done.
//
//  Without Pro, every answer spends the free allowance (AssistantAllowance: 30 in the first
//  week, then 10 a month). A question over the allowance is not sent: it stays in the thread
//  with the Pro offer, and goes once Pro is on (`retry()` after the paywall).
//
//  The thread is kept across launches (AgentThreadStore): written after every reply, brought
//  back by `restore()` when the screen opens, its questions and replies replayed from the
//  conversation itself. A new chat starts another thread.
//

import Foundation
import Observation

@Observable
final class AssistantViewModel {
    /// Who may ask how much: Pro, or the free allowance kept on the device.
    struct Access {
        var isPro: () -> Bool
        var loadUsage: () -> AssistantUsage
        var saveUsage: (AssistantUsage) -> Void
        var now: () -> Date = Date.init

        static let unlimited = Access(isPro: { true }, loadUsage: { AssistantUsage() }, saveUsage: { _ in })
    }

    /// Where the thread is kept between launches (AgentThreadStore).
    struct Persistence {
        var load: () async -> AgentThreadSnapshot?
        var save: (AgentThreadSnapshot) async -> Void
    }

    struct Entry: Identifiable, Equatable {
        enum Content: Equatable {
            case question(String)
            case reply(AgentReply, results: [String: JSONValue])
        }

        let id: UUID
        let content: Content

        var question: String? {
            if case .question(let text) = content { return text }
            return nil
        }
    }

    enum Phase: Equatable {
        case idle
        case working(AssistantStep)
        /// The last question was not answered; it stays in the thread with Retry.
        case failed(AssistantFailure)
    }

    private(set) var entries: [Entry] = []
    private(set) var phase: Phase = .idle
    /// The mood of the latest reply, for the mascot.
    private(set) var replyMood: AgentMood = .idle
    /// The free allowance; nil with Pro.
    private(set) var allowance: AssistantAllowance.Status?
    /// The drafts the replies' confirm cards save; nil where drafting is not wired.
    @ObservationIgnored let drafts: AgentDraftBook?
    /// A draft operation as the draft tools describe it (FinanceToolkit), for an edited draft.
    @ObservationIgnored private let describeDraft: ((AgentDraftOperation) -> JSONValue)?

    @ObservationIgnored private let conversation: AgentConversation
    @ObservationIgnored private let context: () -> String
    @ObservationIgnored private var sentContext: String?
    @ObservationIgnored private var failedEntryId: UUID?
    /// The draft states the model was last told about.
    @ObservationIgnored private var reportedDrafts: [String: String] = [:]
    @ObservationIgnored private let access: Access
    @ObservationIgnored private let persistence: Persistence?
    @ObservationIgnored private var threadId = UUID().uuidString
    @ObservationIgnored private var threadCreatedAt: Date
    /// The kept thread is brought back once, and never over a thread already going.
    @ObservationIgnored private var restoreDone = false

    init(
        conversation: AgentConversation,
        context: @escaping () -> String,
        access: Access = .unlimited,
        drafts: AgentDraftBook? = nil,
        describeDraft: ((AgentDraftOperation) -> JSONValue)? = nil,
        persistence: Persistence? = nil
    ) {
        self.conversation = conversation
        self.context = context
        self.access = access
        self.drafts = drafts
        self.describeDraft = describeDraft
        self.persistence = persistence
        self.threadCreatedAt = access.now()
        refreshAllowance()
    }

    /// Brings back the thread kept last, once, while nothing has been asked yet.
    func restore() async {
        guard !restoreDone, let persistence else { return }
        restoreDone = true
        guard entries.isEmpty, !isWorking, let snapshot = await persistence.load() else { return }
        // A question may have gone while the thread was loading.
        guard entries.isEmpty, !isWorking else { return }
        conversation.restore(snapshot.body)
        entries = Self.entries(replaying: snapshot.body)
        if case .reply(let reply, _)? = entries.last?.content { replyMood = reply.mood }
        threadId = snapshot.id
        threadCreatedAt = snapshot.createdAt
        // The context is in the kept history, but it may be stale: the next question sends it.
        sentContext = nil
        drafts?.continueNumbering(after: Self.lastDraftNumber(in: snapshot.body.results))
    }

    /// The visible thread of a kept conversation: each question (the last text of a user
    /// message, after the context blocks) and each reply (a `render_reply` sent alone; one sent
    /// next to other tools was turned back, AgentConversation).
    static func entries(replaying body: AgentThreadSnapshot.Body) -> [Entry] {
        var entries: [Entry] = []
        for message in body.messages {
            switch message.role {
            case .user:
                if let text = message.content.last(where: { $0["type"] == "text" })?["text"]?.stringValue {
                    entries.append(Entry(id: UUID(), content: .question(text)))
                }
            case .assistant:
                let uses = message.content.compactMap(AgentToolUse.init(block:))
                guard uses.count == 1, let use = uses.first, use.name == AgentProtocol.renderReplyTool,
                      let reply = try? use.input.decoded(as: AgentReply.self) else { continue }
                entries.append(Entry(id: UUID(), content: .reply(reply, results: body.results)))
            }
        }
        return entries
    }

    /// The highest `draft_N` among the results.
    static func lastDraftNumber(in results: [String: JSONValue]) -> Int {
        results.values
            .compactMap { $0["draft_id"]?.stringValue }
            .compactMap { $0.hasPrefix("draft_") ? Int($0.dropFirst("draft_".count)) : nil }
            .max() ?? 0
    }

    private func persist() async {
        guard let persistence else { return }
        await persistence.save(AgentThreadSnapshot(
            id: threadId,
            createdAt: threadCreatedAt,
            updatedAt: access.now(),
            title: entries.lazy.compactMap(\.question).first,
            body: conversation.body
        ))
    }

    /// Re-reads Pro and the allowance (after a purchase, on appearing).
    func refreshAllowance() {
        allowance = access.isPro() ? nil : AssistantAllowance.status(access.loadUsage(), now: access.now())
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    /// The question that failed, to mark it in the thread.
    var failedEntry: UUID? {
        if case .failed = phase { return failedEntryId }
        return nil
    }

    /// The suggestions of the latest reply, while nothing else is going on.
    var suggestions: [String] {
        guard phase == .idle, case .reply(let reply, _)? = entries.last?.content else { return [] }
        return reply.suggestions
    }

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        // A question that failed was never part of the history: moving on drops it.
        if let failedEntryId, case .failed = phase {
            entries.removeAll { $0.id == failedEntryId }
        }
        let entry = Entry(id: UUID(), content: .question(text))
        entries.append(entry)
        await ask(text, entry: entry.id)
    }

    /// A new thread; the next question carries the context again. The old one stays kept.
    func reset() {
        guard !isWorking else { return }
        restoreDone = true
        threadId = UUID().uuidString
        threadCreatedAt = access.now()
        conversation.reset()
        entries = []
        phase = .idle
        replyMood = .idle
        sentContext = nil
        failedEntryId = nil
        drafts?.clear()
        reportedDrafts = [:]
    }

    func retry() async {
        guard case .failed = phase, let failedEntryId,
              let entry = entries.first(where: { $0.id == failedEntryId }),
              case .question(let text) = entry.content else { return }
        await ask(text, entry: failedEntryId)
    }

    /// The drafts saved, undone or edited since the model last heard, as a `<draft_status>`
    /// block, with the states to remember once the turn goes through; nil when nothing changed.
    /// An edited draft carries its items as they are now, so another edit is news again.
    private func draftStatus() -> (text: String, states: [String: String])? {
        guard let drafts else { return nil }
        var states: [String: String] = [:]
        for (id, state) in drafts.states {
            var status: String?
            switch state {
            case .saved: status = "saved"
            case .undone: status = "undone"
            case .pending, .saving, .failed: break
            }
            if drafts.edited.contains(id) {
                var edit = status.map { "\($0), edited by the user before saving" } ?? "edited by the user on the card, not saved yet"
                if let describeDraft, let operations = drafts.drafts[id]?.operations {
                    edit += ", items now: " + JSONValue.array(operations.map(describeDraft)).jsonString()
                }
                status = edit
            }
            if let status { states[id] = status }
        }
        let changed = states.filter { reportedDrafts[$0.key] != $0.value }.sorted { $0.key < $1.key }
        guard !changed.isEmpty else { return nil }
        let lines = changed.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return ("<draft_status>\n\(lines)\n</draft_status>", states)
    }

    private func ask(_ text: String, entry: UUID) async {
        failedEntryId = entry
        refreshAllowance()
        if let allowance, allowance.isExhausted {
            phase = .failed(.freeLimit)
            return
        }
        phase = .working(.understanding)
        if conversation.trimIfNeeded() { sentContext = nil }
        let current = context()
        let contextToSend = current == sentContext ? nil : current
        let status = draftStatus()
        let preface = [contextToSend, status?.text].compactMap { $0 }.joined(separator: "\n")
        do {
            let outcome = try await conversation.send(text, context: preface.isEmpty ? nil : preface) { [weak self] progress in
                guard let self, case .toolStarted(let name) = progress else { return }
                self.phase = .working(AssistantStep(tool: name))
            }
            sentContext = current
            if let status { reportedDrafts = status.states }
            if !access.isPro() {
                access.saveUsage(AssistantAllowance.recording(access.loadUsage(), now: access.now()))
                refreshAllowance()
            }
            entries.append(Entry(id: UUID(), content: .reply(outcome.reply, results: outcome.results)))
            replyMood = outcome.reply.mood
            failedEntryId = nil
            phase = .idle
            await persist()
        } catch {
            phase = .failed(AssistantFailure(error))
        }
    }
}

/// What the assistant is doing, named after the tool it runs.
enum AssistantStep: Equatable {
    case understanding
    case spending
    case comparing
    case searching
    case accounts
    case budgets
    case recurring
    case insights
    /// Forecasts and what-ifs: the balance, a loan, savings.
    case calculating
    case composing

    init(tool: String) {
        switch tool {
        case "get_spending_summary": self = .spending
        case "compare_periods": self = .comparing
        case "search_transactions": self = .searching
        case "get_accounts": self = .accounts
        case "get_budgets": self = .budgets
        case "list_recurring": self = .recurring
        case "get_insights": self = .insights
        case "forecast_balance", "simulate_loan", "project_savings": self = .calculating
        case AgentProtocol.renderReplyTool: self = .composing
        default: self = .understanding
        }
    }

    var title: String {
        switch self {
        case .understanding: String(localized: "assistant.step.understanding")
        case .spending: String(localized: "assistant.step.spending")
        case .comparing: String(localized: "assistant.step.comparing")
        case .searching: String(localized: "assistant.step.searching")
        case .accounts: String(localized: "assistant.step.accounts")
        case .budgets: String(localized: "assistant.step.budgets")
        case .recurring: String(localized: "assistant.step.recurring")
        case .insights: String(localized: "assistant.step.insights")
        case .calculating: String(localized: "assistant.step.calculating")
        case .composing: String(localized: "assistant.step.composing")
        }
    }
}

/// Why a question was not answered, in words for the person.
enum AssistantFailure: Equatable {
    case offline
    case busy
    case limitReached
    case proRequired
    case regionUnavailable
    case unavailable
    case refused
    /// The free answers are used up for now.
    case freeLimit
    case generic

    init(_ error: Error) {
        switch error {
        case let error as AgentServerError:
            switch error {
            case .quotaExceeded: self = .limitReached
            case .busy: self = .busy
            case .unauthorized: self = .proRequired
            case .regionUnavailable: self = .regionUnavailable
            case .disabled, .notConfigured, .entitlementUnavailable: self = .unavailable
            // The server could not verify this app instance; Pro does not change that.
            case .attestation: self = .unavailable
            case .invalidRequest, .http: self = .generic
            }
        case let error as AgentConversationError:
            switch error {
            case .refused: self = .refused
            case .stream(_, let retryable): self = retryable ? .busy : .generic
            case .truncated, .noReply, .invalidReply, .tooManySteps: self = .generic
            }
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            default:
                self = .generic
            }
        default:
            self = .generic
        }
    }

    /// Whether asking again can help.
    var canRetry: Bool {
        switch self {
        case .offline, .busy, .generic: true
        case .limitReached, .proRequired, .regionUnavailable, .unavailable, .refused, .freeLimit: false
        }
    }

    var message: String {
        switch self {
        case .offline: String(localized: "assistant.error.offline")
        case .busy: String(localized: "assistant.error.busy")
        case .limitReached: String(localized: "assistant.error.limit")
        case .proRequired: String(localized: "assistant.error.pro")
        case .regionUnavailable: String(localized: "assistant.error.region")
        case .unavailable: String(localized: "assistant.error.unavailable")
        case .refused: String(localized: "assistant.error.refused")
        case .freeLimit: String(localized: "assistant.error.freeLimit")
        case .generic: String(localized: "assistant.error.generic")
        }
    }
}
