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
//  conversation itself. A new chat starts another thread; a kept one can be opened again or
//  deleted from the assistant's home.
//
//  FastPath (AgentFastPath, plan §3.8): a message the phone's parser understands as income or
//  expenses becomes a draft on the phone, without the cloud and without the consent the cloud
//  needs. Typed, it is free; spoken, it spends one free answer, as voice does. The model hears
//  about such a draft with the next question, in <draft_status>; the thread keeps where it
//  sits (`AgentThreadSnapshot.LocalExchange`).
//
//  An attachment (a receipt or a statement read on the phone, AgentAttachment) joins the thread
//  as its summary card. The model sees the summary with the next question, as an
//  <attachment_result> block. Opening its review spends one free answer, once (plan §6:
//  reading is free, the limit is checked where the work is taken). Attachments are not kept
//  across launches.
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

    /// Drafts a message on the phone when it is a plain record (AgentFastPath); nil sends it to
    /// the model.
    struct FastPath {
        var draft: (String) async -> [AgentDraftOperation]?
    }

    /// Where the thread is kept between launches (AgentThreadStore).
    struct Persistence {
        var load: () async -> AgentThreadSnapshot?
        var save: (AgentThreadSnapshot) async -> Void
        /// The latest kept threads, newest first, at most this many.
        var recent: (Int) async -> [AgentThreadSummary] = { _ in [] }
        /// One kept thread by id.
        var thread: (String) async -> AgentThreadSnapshot? = { _ in nil }
        /// Deletes a kept thread.
        var delete: (String) async -> Void = { _ in }
    }

    /// The kept threads the home lists, the open one aside.
    static let recentLimit = 5

    struct Entry: Identifiable, Equatable {
        enum Content: Equatable {
            case question(String)
            case reply(AgentReply, results: [String: JSONValue])
            case attachment(AgentAttachmentSummary)
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
    /// The reply's text blocks while the model writes them; empty otherwise. The finished
    /// reply takes their place.
    private(set) var streamingReply: [String] = []
    /// The latest kept threads but the open one, for the history (at most `recentLimit`).
    private(set) var recentThreads: [AgentThreadSummary] = []
    /// The free allowance; nil with Pro.
    private(set) var allowance: AssistantAllowance.Status?
    /// The drafts the replies' confirm cards save; nil where drafting is not wired.
    @ObservationIgnored let drafts: AgentDraftBook?
    /// A draft operation as the draft tools describe it (FinanceToolkit), for an edited draft.
    @ObservationIgnored private let describeDraft: ((AgentDraftOperation) -> JSONValue)?

    @ObservationIgnored private let conversation: AgentConversation
    /// The `<app_context>` block; async, as the remembered facts may still be loading.
    @ObservationIgnored private let context: @MainActor () async -> String
    @ObservationIgnored private var sentContext: String?
    @ObservationIgnored private var failedEntryId: UUID?
    /// The draft states the model was last told about.
    @ObservationIgnored private var reportedDrafts: [String: String] = [:]
    @ObservationIgnored private let access: Access
    @ObservationIgnored private let persistence: Persistence?
    @ObservationIgnored private let fastPath: FastPath?
    /// The messages answered on the phone, with where they sit in the thread.
    @ObservationIgnored private var local: [AgentThreadSnapshot.LocalExchange] = []
    /// A message is being drafted on the phone: another waits.
    @ObservationIgnored private var draftingLocally = false
    /// What each attachment's review screen needs, by its entry.
    @ObservationIgnored private var attachments: [UUID: AgentAttachment] = [:]
    /// The attachments whose review has been paid for.
    @ObservationIgnored private var reviewedAttachments: Set<UUID> = []
    /// Blocks the model has not seen (attachment summaries, the message being gone through):
    /// they go with the next question.
    @ObservationIgnored private var unsentNotes: [String] = []
    /// The open thread's id.
    @ObservationIgnored private(set) var threadId = UUID().uuidString
    @ObservationIgnored private var threadCreatedAt: Date
    /// When the open thread was last written.
    @ObservationIgnored private var threadUpdatedAt: Date
    /// The kept thread is brought back once, and never over a thread already going.
    @ObservationIgnored private var restoreDone = false

    init(
        conversation: AgentConversation,
        context: @escaping @MainActor () async -> String,
        access: Access = .unlimited,
        drafts: AgentDraftBook? = nil,
        describeDraft: ((AgentDraftOperation) -> JSONValue)? = nil,
        fastPath: FastPath? = nil,
        persistence: Persistence? = nil
    ) {
        self.conversation = conversation
        self.context = context
        self.access = access
        self.drafts = drafts
        self.describeDraft = describeDraft
        self.fastPath = fastPath
        self.persistence = persistence
        self.threadCreatedAt = access.now()
        self.threadUpdatedAt = access.now()
        refreshAllowance()
    }

    /// Brings back the thread kept last, once, while nothing has been asked yet.
    func restore() async {
        guard !restoreDone, let persistence else { return }
        restoreDone = true
        defer { Task { await refreshRecent() } }
        guard entries.isEmpty, !isWorking, let snapshot = await persistence.load() else { return }
        // A question may have gone while the thread was loading.
        guard entries.isEmpty, !isWorking else { return }
        apply(snapshot)
    }

    /// Opens a kept thread from the history in place of the open one, which stays kept.
    /// True when that thread is the open one now (it may have been already).
    @discardableResult
    func open(threadId id: String) async -> Bool {
        if id == threadId { return true }
        guard !isWorking, !draftingLocally, let persistence,
              let snapshot = await persistence.thread(id), !isWorking else { return false }
        restoreDone = true
        clearThreadState()
        apply(snapshot)
        await refreshRecent()
        return true
    }

    /// Deletes a kept thread; the open one is left for a new, empty one.
    func deleteThread(_ id: String) async {
        guard let persistence else { return }
        if id == threadId {
            guard !isWorking, !draftingLocally else { return }
            reset()
        }
        await persistence.delete(id)
        await refreshRecent()
    }

    /// The open thread as the home lists it, once something is in it: its first question,
    /// else what was attached.
    var currentThread: AgentThreadSummary? {
        guard !entries.isEmpty else { return nil }
        let title = entries.lazy.compactMap(\.question).first ?? entries.lazy.compactMap { entry -> String? in
            guard case .attachment(let summary) = entry.content else { return nil }
            return summary.title ?? (summary.kind == .receipt
                ? String(localized: "assistant.attachment.receipt")
                : String(localized: "assistant.attachment.statement"))
        }.first ?? ""
        return AgentThreadSummary(id: threadId, title: title, updatedAt: threadUpdatedAt)
    }

    /// Re-reads the history.
    func refreshRecent() async {
        guard let persistence else { return }
        let open = threadId
        let kept = await persistence.recent(Self.recentLimit + 1)
        recentThreads = Array(kept.filter { $0.id != open }.prefix(Self.recentLimit))
    }

    /// A kept thread on screen: its history goes back to the conversation, its questions and
    /// replies to the thread.
    private func apply(_ snapshot: AgentThreadSnapshot) {
        conversation.restore(snapshot.body)
        local = snapshot.body.local
        entries = Self.entries(replaying: snapshot.body)
        if case .reply(let reply, _)? = entries.last?.content { replyMood = reply.mood } else { replyMood = .idle }
        threadId = snapshot.id
        threadCreatedAt = snapshot.createdAt
        threadUpdatedAt = snapshot.updatedAt
        // The context is in the kept history, but it may be stale: the next question sends it.
        sentContext = nil
        drafts?.continueNumbering(after: Self.lastDraftNumber(in: snapshot.body))
    }

    /// What belongs to the thread on screen and is not kept with it: drafts, attachments, a
    /// failed question, the step and the streamed reply.
    private func clearThreadState() {
        phase = .idle
        failedEntryId = nil
        streamingReply = []
        drafts?.clear()
        reportedDrafts = [:]
        local = []
        attachments = [:]
        reviewedAttachments = []
        unsentNotes = []
    }

    /// The visible thread of a kept conversation: each question (the last text of a user
    /// message, after the context blocks) and each reply (a `render_reply` sent alone; one sent
    /// next to other tools was turned back, AgentConversation). The messages the phone answered
    /// sit where they were.
    static func entries(replaying body: AgentThreadSnapshot.Body) -> [Entry] {
        var entries: [Entry] = []
        var local = body.local[...]
        func appendLocal(upTo position: Int) {
            while let exchange = local.first, exchange.position <= position {
                entries.append(Entry(id: UUID(), content: .question(exchange.question)))
                entries.append(Entry(id: UUID(), content: .reply(Self.localReply(exchange.draftId), results: [:])))
                local = local.dropFirst()
            }
        }
        for (index, message) in body.messages.enumerated() {
            appendLocal(upTo: index)
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
        appendLocal(upTo: .max)
        return entries
    }

    /// The reply to a message the phone answered: its draft's confirm card.
    static func localReply(_ draftId: String) -> AgentReply {
        AgentReply(blocks: [.confirm(draftId: draftId)], mood: .happy, suggestions: [])
    }

    /// The highest `draft_N` of the thread, among the results and the drafts made on the phone.
    static func lastDraftNumber(in body: AgentThreadSnapshot.Body) -> Int {
        (body.results.values.compactMap { $0["draft_id"]?.stringValue } + body.local.map(\.draftId))
            .compactMap { $0.hasPrefix("draft_") ? Int($0.dropFirst("draft_".count)) : nil }
            .max() ?? 0
    }

    private func persist() async {
        guard let persistence else { return }
        threadUpdatedAt = access.now()
        await persistence.save(AgentThreadSnapshot(
            id: threadId,
            createdAt: threadCreatedAt,
            updatedAt: threadUpdatedAt,
            title: entries.lazy.compactMap(\.question).first,
            body: { var body = conversation.body; body.local = local; return body }()
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

    /// The suggestions of the latest reply, while nothing else is going on; after a statement,
    /// to go through it.
    var suggestions: [String] {
        guard phase == .idle else { return [] }
        switch entries.last?.content {
        case .reply(let reply, _)?: return reply.suggestions
        case .attachment(let summary)? where summary.kind == .statement:
            return [String(localized: "assistant.attachment.analyze")]
        default: return []
        }
    }

    // MARK: - Ten writes first

    /// "Go through it" on a message Ten wrote first: its question, with the message for the
    /// model (a `<notice>` block). The message counts as read. False when nothing went (the
    /// cloud is not allowed yet).
    @discardableResult
    func ask(about notice: AssistantNotice, cloudAllowed: Bool = true) async -> Bool {
        guard cloudAllowed, !isWorking, !draftingLocally else { return false }
        unsentNotes.append(notice.modelText)
        let sent = await send(notice.question, cloudAllowed: cloudAllowed, phoneMayAnswer: false)
        if !sent { unsentNotes.removeAll { $0 == notice.modelText } }
        return sent
    }

    // MARK: - Attachments

    /// A receipt or a statement read on the phone joins the thread as its summary card.
    func attach(_ attachment: AgentAttachment, summary: AgentAttachmentSummary) {
        let entry = Entry(id: UUID(), content: .attachment(summary))
        attachments[entry.id] = attachment
        unsentNotes.append(summary.modelText)
        dropFailedQuestion()
        entries.append(entry)
    }

    /// What the attachment's review screen needs.
    func attachment(for entry: UUID) -> AgentAttachment? {
        attachments[entry]
    }

    /// Takes the work of an attachment: Pro, or one free answer the first time. False when
    /// none is left; the caller offers Pro.
    func payForReview(of entry: UUID) -> Bool {
        if access.isPro() || reviewedAttachments.contains(entry) { return true }
        refreshAllowance()
        guard allowance?.isExhausted != true else { return false }
        access.saveUsage(AssistantAllowance.recording(access.loadUsage(), now: access.now()))
        refreshAllowance()
        reviewedAttachments.insert(entry)
        return true
    }

    /// Sends a question, or drafts it on the phone when it is a plain record (FastPath).
    /// - Parameters:
    ///   - spoken: it came from the voice sheet: a FastPath draft spends a free answer.
    ///   - cloudAllowed: the person agreed to the cloud mode. Without it only FastPath goes.
    ///   - phoneMayAnswer: FastPath may take it; off for a question the app wrote itself.
    /// - Returns: false when nothing happened: the message needs the cloud, which is not allowed.
    @discardableResult
    func send(_ raw: String, spoken: Bool = false, cloudAllowed: Bool = true, phoneMayAnswer: Bool = true) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking, !draftingLocally else { return false }
        if phoneMayAnswer, let operations = await draftOnPhone(text, spoken: spoken), let drafts {
            dropFailedQuestion()
            let id = drafts.add(operations, madeOnPhoneFrom: text)
            local.append(AgentThreadSnapshot.LocalExchange(position: conversation.messages.count, question: text, draftId: id))
            entries.append(Entry(id: UUID(), content: .question(text)))
            entries.append(Entry(id: UUID(), content: .reply(Self.localReply(id), results: [:])))
            replyMood = .happy
            phase = .idle
            await persist()
            return true
        }
        guard cloudAllowed else { return false }
        dropFailedQuestion()
        let entry = Entry(id: UUID(), content: .question(text))
        entries.append(entry)
        await ask(text, entry: entry.id)
        return true
    }

    /// A question that failed was never part of the history: moving on drops it.
    private func dropFailedQuestion() {
        guard let failedEntryId, case .failed = phase else { return }
        entries.removeAll { $0.id == failedEntryId }
        self.failedEntryId = nil
        phase = .idle
    }

    /// The message as a draft made on the phone, or nil for the model. A spoken one spends a
    /// free answer, and with none left goes the usual way (which then offers Pro).
    private func draftOnPhone(_ text: String, spoken: Bool) async -> [AgentDraftOperation]? {
        guard let fastPath, drafts != nil else { return nil }
        let charged = spoken && !access.isPro()
        if charged {
            refreshAllowance()
            if allowance?.isExhausted == true { return nil }
        }
        draftingLocally = true
        defer { draftingLocally = false }
        guard let operations = await fastPath.draft(text), !operations.isEmpty else { return nil }
        if charged {
            access.saveUsage(AssistantAllowance.recording(access.loadUsage(), now: access.now()))
            refreshAllowance()
        }
        return operations
    }

    /// A new thread; the next question carries the context again. The old one stays kept.
    func reset() {
        guard !isWorking else { return }
        restoreDone = true
        threadId = UUID().uuidString
        threadCreatedAt = access.now()
        threadUpdatedAt = access.now()
        conversation.reset()
        entries = []
        replyMood = .idle
        sentContext = nil
        clearThreadState()
        // The thread just left is in the history now.
        Task { await refreshRecent() }
    }

    /// "Delete all data" or a restored backup replaced the store: the open thread, its drafts
    /// and attachments belong to the old data, and must neither show nor be written into the
    /// new store. The next appearance brings back the new store's latest thread, if any.
    func storeDidReset() {
        conversation.reset()
        entries = []
        replyMood = .idle
        sentContext = nil
        clearThreadState()
        threadId = UUID().uuidString
        threadCreatedAt = access.now()
        threadUpdatedAt = access.now()
        restoreDone = false
        recentThreads = []
        Task { await refreshRecent() }
    }

    func retry() async {
        guard case .failed = phase, let failedEntryId,
              let entry = entries.first(where: { $0.id == failedEntryId }),
              case .question(let text) = entry.content else { return }
        await ask(text, entry: failedEntryId)
    }

    /// The drafts saved, undone or edited since the model last heard, and the ones the phone
    /// made without it, as a `<draft_status>` block, with the states to remember once the turn
    /// goes through; nil when nothing changed. An edited draft or one made on the phone carries
    /// its items as they are now, so another edit is news again.
    private func draftStatus() -> (text: String, states: [String: String])? {
        guard let drafts else { return nil }
        var states: [String: String] = [:]
        for (id, state) in drafts.states {
            let edited = drafts.edited.contains(id)
            let message = drafts.madeOnPhone[id]
            var status: String?
            switch state {
            case .saved: status = "saved"
            case .undone: status = "undone"
            case .pending, .saving, .failed: break
            }
            if edited {
                status = status.map { "\($0), edited by the user before saving" } ?? "edited by the user on the card, not saved yet"
            }
            if let message {
                status = "made on the phone from the user's message \"\(message)\", not by you; " + (status ?? "not saved yet")
            }
            if edited || message != nil, var line = status, let describeDraft, let operations = drafts.drafts[id]?.operations {
                line += ", items now: " + JSONValue.array(operations.map(describeDraft)).jsonString()
                status = line
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
        let kept = conversation.messages.count
        if conversation.trimIfNeeded() {
            sentContext = nil
            // The messages answered on the phone move up with the thread; older ones go.
            let removed = kept - conversation.messages.count
            local = local.compactMap { exchange in
                guard exchange.position >= removed else { return nil }
                var moved = exchange
                moved.position -= removed
                return moved
            }
        }
        let current = await context()
        let contextToSend = current == sentContext ? nil : current
        let status = draftStatus()
        let attached = unsentNotes
        let preface = [contextToSend, status?.text].compactMap { $0 }.joined(separator: "\n")
        do {
            let outcome = try await conversation.send(text, context: preface.isEmpty ? nil : preface, notes: attached) { [weak self] progress in
                guard let self else { return }
                switch progress {
                case .toolStarted(let name):
                    self.phase = .working(AssistantStep(tool: name))
                    // Another tool after a streamed reply: that reply was turned back.
                    if name != AgentProtocol.renderReplyTool { self.streamingReply = [] }
                case .replyText(let texts):
                    self.streamingReply = texts
                }
            }
            streamingReply = []
            sentContext = current
            if let status { reportedDrafts = status.states }
            unsentNotes.removeFirst(min(attached.count, unsentNotes.count))
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
            streamingReply = []
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
    /// Savings goals and personal debts.
    case plans
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
        case "get_goals", "get_debts": self = .plans
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
        case .plans: String(localized: "assistant.step.plans")
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
