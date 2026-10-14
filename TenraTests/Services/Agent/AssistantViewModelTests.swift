//
//  AssistantViewModelTests.swift
//  TenraTests
//
//  The assistant screen's state over a scripted server: the thread of questions and replies,
//  the step named after the running tool, a failed question kept for Retry, and the
//  <app_context> block sent only when it changed, the free allowance checked before a
//  question goes out, and the thread kept across launches.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantViewModelTests {

    private func makeModel(
        _ transport: AgentTransport,
        context: @escaping () -> String = { "<app_context>a</app_context>" },
        access: AssistantViewModel.Access = .unlimited
    ) -> AssistantViewModel {
        AssistantViewModel(conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()), context: context, access: access)
    }

    /// The free allowance kept in memory instead of the Keychain.
    @MainActor
    private final class UsageBox {
        var usage: AssistantUsage
        var isPro = false
        init(_ usage: AssistantUsage = AssistantUsage()) { self.usage = usage }

        func access(now: Date) -> AssistantViewModel.Access {
            AssistantViewModel.Access(isPro: { self.isPro }, loadUsage: { self.usage }, saveUsage: { self.usage = $0 }, now: { now })
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aQuestionAndItsReplyJoinTheThread() async {
        let transport = ScriptedTransport([
            [.tool(name: "get_accounts"), AgentScript.done([AgentScript.toolUse("toolu_1", "get_accounts")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "r1", mood: "celebrate", suggestions: ["Ещё"])])],
        ])
        let model = makeModel(transport)

        await model.send("  Сколько у меня денег?  ")

        #expect(model.phase == .idle)
        #expect(model.entries.count == 2)
        #expect(model.entries.first?.content == .question("Сколько у меня денег?"))
        guard case .reply(let reply, let results)? = model.entries.last?.content else {
            Issue.record("expected a reply")
            return
        }
        #expect(reply.mood == .celebrate)
        #expect(results["r1"]?["total_base"] == .number(2_334_450))
        #expect(model.replyMood == .celebrate)
        #expect(model.suggestions == ["Ещё"])
    }

    @Test func blankQuestionsAreIgnored() async {
        let transport = ScriptedTransport([])
        let model = makeModel(transport)
        await model.send("   ")
        #expect(model.entries.isEmpty)
        #expect(transport.calls.isEmpty)
    }

    @Test func theContextGoesOnlyWhenItChanged() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_3", source: "none")])],
        ])
        var context = "<app_context>day 1</app_context>"
        let model = makeModel(transport, context: { context })

        await model.send("Первый")
        await model.send("Второй")
        context = "<app_context>day 2</app_context>"
        await model.send("Третий")

        let firsts = transport.calls.map { call in call.last?.content.compactMap { $0["text"]?.stringValue } ?? [] }
        #expect(firsts[0] == ["<app_context>day 1</app_context>", "Первый"])
        #expect(firsts[1] == ["Второй"])
        #expect(firsts[2] == ["<app_context>day 2</app_context>", "Третий"])
    }

    @Test func aFailedQuestionStaysForRetry() async {
        let transport = ScriptedTransport([
            [.error(code: "upstream_busy", retryable: true)],
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
        ])
        let model = makeModel(transport)

        await model.send("Сколько на кафе?")
        #expect(model.phase == .failed(.busy))
        #expect(model.entries.count == 1)
        #expect(model.failedEntry == model.entries.first?.id)
        #expect(model.suggestions.isEmpty)

        await model.retry()
        #expect(model.phase == .idle)
        #expect(model.entries.count == 2)
        #expect(model.failedEntry == nil)
        // The retry sends the same question again, with the context it never delivered.
        let retried = transport.calls[1].last?.content.compactMap { $0["text"]?.stringValue }
        #expect(retried == ["<app_context>a</app_context>", "Сколько на кафе?"])
    }

    @Test func movingOnDropsTheFailedQuestion() async {
        let transport = ScriptedTransport([
            [.error(code: "internal", retryable: false)],
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
        ])
        let model = makeModel(transport)

        await model.send("Первый")
        #expect(model.phase == .failed(.generic))
        await model.send("Второй")

        #expect(model.entries.count == 2)
        #expect(model.entries.first?.content == .question("Второй"))
    }

    @Test func serverErrorsBecomeWordsForThePerson() async {
        let limit = makeModel(FailingTransport(AgentServerError.quotaExceeded(limit: 900)))
        await limit.send("…")
        #expect(limit.phase == .failed(.limitReached))
        #expect(AssistantFailure.limitReached.canRetry == false)

        let offline = makeModel(FailingTransport(URLError(.notConnectedToInternet)))
        await offline.send("…")
        #expect(offline.phase == .failed(.offline))
        #expect(AssistantFailure.offline.canRetry)

        #expect(AssistantFailure(AgentServerError.unauthorized) == .proRequired)
        #expect(AssistantFailure(AgentServerError.regionUnavailable) == .regionUnavailable)
        #expect(AssistantFailure(AgentConversationError.refused) == .refused)
    }

    @Test func aNewChatForgetsTheThread() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
        ])
        let model = makeModel(transport)

        await model.send("Первый")
        model.reset()
        #expect(model.entries.isEmpty)
        await model.send("Второй")

        // A fresh thread: one user message, with the context again and no owed result.
        let fresh = transport.calls[1]
        #expect(fresh.count == 1)
        #expect(fresh[0].content.compactMap { $0["text"]?.stringValue } == ["<app_context>a</app_context>", "Второй"])
        #expect(fresh[0].content.count == 2)
    }

    @Test func aNewChatClearsItsDrafts() {
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(save: { _ in throw FinanceToolError(message: "unused") }, undo: { _ in }))
        _ = book.add([])
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit()),
            context: { "" },
            drafts: book
        )
        model.reset()
        #expect(book.drafts.isEmpty)
    }

    @Test func savedDraftsAreReportedOnce() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_3", source: "none")])],
        ])
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { _ in .transaction(Transaction(id: "tx1", date: "2026-10-28", description: "", amount: 1, currency: "KZT", type: .expense, category: "")) },
            undo: { _ in }
        ))
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            drafts: book
        )

        await model.send("Кофе 1500")
        let id = book.add([])
        await book.save(id)
        await model.send("Ещё такси")
        await model.send("Сколько на кафе?")

        let texts = transport.calls.map { call in call.last?.content.compactMap { $0["text"]?.stringValue } ?? [] }
        #expect(texts[1] == ["<draft_status>\ndraft_1: saved\n</draft_status>", "Ещё такси"])
        #expect(texts[2] == ["Сколько на кафе?"])
    }

    @Test func anEditedDraftIsReportedWithWhatItHoldsNow() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_3", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_4", source: "none")])],
        ])
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { _ in .transaction(Transaction(id: "tx1", date: "2026-10-28", description: "", amount: 1, currency: "KZT", type: .expense, category: "")) },
            undo: { _ in }
        ))
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            drafts: book,
            describeDraft: { operation in
                guard case .single(let draft) = operation else { return .null }
                return ["amount": .number(draft.amount)]
            }
        )
        func expense(_ amount: Double) -> AgentDraftOperation {
            .single(TransactionDraft(type: .expense, amount: amount, currency: "KZT", convertedAmount: nil, categoryName: "Кафе", subcategoryIds: [], accountId: "acc_kaspi", date: Self.now, note: "", warnings: []))
        }

        await model.send("Кофе 1500")
        let id = book.add([expense(1500)])
        book.replace(id, at: 0, with: expense(1800))
        await model.send("Что там с кофе?")
        await model.send("А на такси?")
        await book.save(id)
        await model.send("Готово?")

        let texts = transport.calls.map { call in call.last?.content.compactMap { $0["text"]?.stringValue } ?? [] }
        #expect(texts[1] == ["<draft_status>\ndraft_1: edited by the user on the card, not saved yet, items now: [{\"amount\":1800}]\n</draft_status>", "Что там с кофе?"])
        #expect(texts[2] == ["А на такси?"])
        #expect(texts[3] == ["<draft_status>\ndraft_1: saved, edited by the user before saving, items now: [{\"amount\":1800}]\n</draft_status>", "Готово?"])
    }

    @Test func aFreeAnswerSpendsTheAllowance() async {
        let transport = ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_1", source: "none")])]])
        let box = UsageBox()
        let model = makeModel(transport, access: box.access(now: Self.now))
        #expect(model.allowance?.remaining == PremiumConfig.Assistant.trialActions)

        await model.send("Сколько на кафе?")

        #expect(model.phase == .idle)
        #expect(box.usage.trialUsed == 1)
        #expect(box.usage.firstUse == Self.now)
        #expect(model.allowance?.remaining == PremiumConfig.Assistant.trialActions - 1)
    }

    @Test func aFailedAnswerCostsNothing() async {
        let box = UsageBox()
        let model = makeModel(FailingTransport(AgentServerError.busy), access: box.access(now: Self.now))
        await model.send("…")
        #expect(model.phase == .failed(.busy))
        #expect(box.usage == AssistantUsage())
    }

    @Test func overTheAllowanceTheQuestionWaitsForPro() async {
        let transport = ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_1", source: "none")])]])
        let box = UsageBox(AssistantUsage(firstUse: Self.now.addingTimeInterval(-3600), trialUsed: PremiumConfig.Assistant.trialActions))
        let model = makeModel(transport, access: box.access(now: Self.now))
        #expect(model.allowance?.isExhausted == true)

        await model.send("Сколько на кафе?")
        #expect(transport.calls.isEmpty)
        #expect(model.phase == .failed(.freeLimit))
        #expect(model.failedEntry == model.entries.first?.id)
        #expect(AssistantFailure.freeLimit.canRetry == false)

        // Pro bought: the paywall's unlock retries the question that waited.
        box.isPro = true
        model.refreshAllowance()
        #expect(model.allowance == nil)
        await model.retry()
        #expect(transport.calls.count == 1)
        #expect(model.phase == .idle)
        #expect(model.entries.count == 2)
        #expect(box.usage.trialUsed == PremiumConfig.Assistant.trialActions)
    }

    @Test func proSpendsNoAllowance() async {
        let transport = ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_1", source: "none")])]])
        let box = UsageBox()
        box.isPro = true
        let model = makeModel(transport, access: box.access(now: Self.now))
        await model.send("Сколько на кафе?")
        #expect(model.allowance == nil)
        #expect(box.usage == AssistantUsage())
    }

    /// The kept thread in memory instead of CoreData.
    @MainActor
    private final class ThreadBox {
        var saved: AgentThreadSnapshot?
        var persistence: AssistantViewModel.Persistence {
            AssistantViewModel.Persistence(load: { self.saved }, save: { self.saved = $0 })
        }
    }

    @Test func aThreadComesBackAfterARelaunch() async throws {
        let box = ThreadBox()
        let first = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([
                [AgentScript.done([AgentScript.toolUse("toolu_1", "get_accounts")])],
                [AgentScript.done([AgentScript.render("toolu_2", source: "r1", mood: "celebrate")])],
            ]), toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            persistence: box.persistence
        )
        await first.send("Сколько у меня денег?")
        let kept = try #require(box.saved)
        #expect(kept.title == "Сколько у меня денег?")

        // A new launch: the thread comes back, and the next question continues it.
        let transport = ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_3", source: "r1")])]])
        let second = AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            persistence: box.persistence
        )
        await second.restore()
        #expect(second.entries.count == 2)
        #expect(second.entries.first?.content == .question("Сколько у меня денег?"))
        guard case .reply(let reply, let results)? = second.entries.last?.content else {
            Issue.record("expected a reply")
            return
        }
        #expect(reply.mood == .celebrate)
        #expect(results["r1"]?["total_base"] == .number(2_334_450))
        #expect(second.replyMood == .celebrate)

        await second.send("А на депозите?")
        let sent = try #require(transport.calls.first)
        #expect(sent.count == kept.body.messages.count + 1)
        // The context goes again: the kept one may be stale.
        #expect(sent.last?.content.contains { $0["text"] == "<app_context>a</app_context>" } == true)
        #expect(box.saved?.id == kept.id)
    }

    @Test func aNewChatIsAnotherThread() async throws {
        let box = ThreadBox()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([
                [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
                [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
            ]), toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            persistence: box.persistence
        )
        await model.send("Привет")
        let firstId = try #require(box.saved?.id)
        model.reset()
        await model.send("Ещё")
        #expect(box.saved?.id != firstId)
        #expect(box.saved?.title == "Ещё")
    }

    @Test func aKeptChatOpensFromTheHistory() async throws {
        let older = AgentThreadSnapshot(
            id: "older",
            createdAt: Self.now,
            updatedAt: Self.now,
            title: "Сколько на кафе?",
            body: AgentThreadSnapshot.Body(
                messages: [
                    AgentWireMessage(role: .user, content: [["type": "text", "text": "Сколько на кафе?"]]),
                    AgentWireMessage(role: .assistant, content: [AgentScript.render("toolu_1", source: "none", mood: "concerned")]),
                ],
                results: [:],
                owedResults: []
            )
        )
        let summaries = [
            AgentThreadSummary(id: "older", title: "Сколько на кафе?", updatedAt: Self.now),
            AgentThreadSummary(id: "oldest", title: "Привет", updatedAt: Self.now.addingTimeInterval(-60)),
        ]
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_2", source: "none")])]]), toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            persistence: AssistantViewModel.Persistence(
                load: { nil },
                save: { _ in },
                recent: { limit in Array(summaries.prefix(limit)) },
                thread: { id in id == "older" ? older : nil }
            )
        )

        await model.refreshRecent()
        #expect(model.recentThreads.map(\.id) == ["older", "oldest"])

        await model.open(threadId: "older")
        #expect(model.entries.compactMap(\.question) == ["Сколько на кафе?"])
        #expect(model.entries.count == 2)
        #expect(model.replyMood == .concerned)
        // The open chat is not in its own history.
        #expect(model.recentThreads.map(\.id) == ["oldest"])
        // A missing one leaves the screen as it is.
        await model.open(threadId: "gone")
        #expect(model.entries.count == 2)
    }

    /// Kept threads in memory, several of them.
    @MainActor
    private final class ThreadShelf {
        var threads: [String: AgentThreadSnapshot] = [:]
        var persistence: AssistantViewModel.Persistence {
            AssistantViewModel.Persistence(
                load: { self.threads.values.max { $0.updatedAt < $1.updatedAt } },
                save: { self.threads[$0.id] = $0 },
                recent: { limit in
                    Array(self.threads.values
                        .filter { $0.title != nil }
                        .sorted { $0.updatedAt > $1.updatedAt }
                        .prefix(limit)
                        .map { AgentThreadSummary(id: $0.id, title: $0.title ?? "", updatedAt: $0.updatedAt) })
                },
                thread: { self.threads[$0] },
                delete: { self.threads[$0] = nil }
            )
        }
    }

    @Test func theOpenChatIsListedOnTheHomeAndCanBeDeleted() async throws {
        let shelf = ThreadShelf()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([
                [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
                [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
            ]), toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            persistence: shelf.persistence
        )
        // Nothing asked yet: nothing to list.
        #expect(model.currentThread == nil)

        await model.send("Сколько на кафе?")
        let first = try #require(model.currentThread)
        #expect(first.id == model.threadId)
        #expect(first.title == "Сколько на кафе?")
        // Opening the open chat is a no-op that succeeds; a missing one fails.
        #expect(await model.open(threadId: first.id))
        #expect(!(await model.open(threadId: "gone")))

        model.reset()
        await model.send("Ещё")
        await model.refreshRecent()
        #expect(model.recentThreads.map(\.id) == [first.id])

        // Deleting another chat leaves the open one; deleting the open one starts an empty one.
        await model.deleteThread(first.id)
        #expect(shelf.threads[first.id] == nil)
        #expect(model.recentThreads.isEmpty)
        #expect(model.currentThread?.title == "Ещё")
        let second = model.threadId
        await model.deleteThread(second)
        #expect(shelf.threads.isEmpty)
        #expect(model.entries.isEmpty)
        #expect(model.currentThread == nil)
        #expect(model.threadId != second)
    }

    @Test func draftsNumberOnFromAKeptThread() {
        let results: [String: JSONValue] = ["r1": ["draft_id": "draft_2"], "r2": ["draft_id": "draft_7"], "r3": ["total": 1]]
        #expect(AssistantViewModel.lastDraftNumber(in: AgentThreadSnapshot.Body(messages: [], results: results, owedResults: [])) == 7)
        // A draft the phone made counts too.
        let local = [AgentThreadSnapshot.LocalExchange(position: 0, question: "кофе 1500", draftId: "draft_9")]
        #expect(AssistantViewModel.lastDraftNumber(in: AgentThreadSnapshot.Body(messages: [], results: results, owedResults: [], local: local)) == 9)
    }

    // MARK: - FastPath

    private static func coffee(_ amount: Double = 1500) -> AgentDraftOperation {
        .single(TransactionDraft(type: .expense, amount: amount, currency: "KZT", convertedAmount: nil, categoryName: "Кафе", subcategoryIds: [], accountId: "acc_kaspi", date: now, note: "кофе", warnings: []))
    }

    private static func book() -> AgentDraftBook {
        AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { _ in .transaction(Transaction(id: "tx1", date: "2026-10-28", description: "", amount: 1, currency: "KZT", type: .expense, category: "")) },
            undo: { _ in }
        ))
    }

    /// Drafts "кофе …" on the phone, sends anything else to the model.
    private static let coffeeFastPath = AssistantViewModel.FastPath { text in
        text.hasPrefix("кофе") ? [coffee()] : nil
    }

    @Test func aPlainRecordIsDraftedOnThePhoneWithoutTheCloud() async {
        let transport = ScriptedTransport([])
        let book = Self.book()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            drafts: book,
            fastPath: Self.coffeeFastPath
        )

        #expect(await model.send("кофе 1500", cloudAllowed: false))

        #expect(transport.calls.isEmpty)
        #expect(model.phase == .idle)
        #expect(model.entries.map(\.content) == [.question("кофе 1500"), .reply(AssistantViewModel.localReply("draft_1"), results: [:])])
        #expect(book.drafts["draft_1"]?.operations == [Self.coffee()])
        #expect(book.madeOnPhone == ["draft_1": "кофе 1500"])

        // A question needs the cloud: without consent nothing happens.
        #expect(await model.send("Сколько на кафе?", cloudAllowed: false) == false)
        #expect(model.entries.count == 2)
    }

    @Test func aSpokenRecordSpendsAFreeAnswerATypedOneDoesNot() async {
        let usage = UsageBox()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit()),
            context: { "" },
            access: usage.access(now: Self.now),
            drafts: Self.book(),
            fastPath: Self.coffeeFastPath
        )

        await model.send("кофе 1500")
        #expect(usage.usage.trialUsed == 0)
        await model.send("кофе 900", spoken: true)
        #expect(usage.usage.trialUsed == 1)
        #expect(model.allowance?.remaining == PremiumConfig.Assistant.trialActions - 1)
    }

    @Test func aSpokenRecordWithNoFreeAnswersLeftOffersPro() async {
        let usage = UsageBox(AssistantUsage(firstUse: Self.now, trialUsed: PremiumConfig.Assistant.trialActions))
        let book = Self.book()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit()),
            context: { "" },
            access: usage.access(now: Self.now),
            drafts: book,
            fastPath: Self.coffeeFastPath
        )

        await model.send("кофе 900", spoken: true)

        #expect(book.drafts.isEmpty)
        #expect(model.phase == .failed(.freeLimit))
    }

    @Test func theModelHearsAboutTheDraftMadeOnThePhone() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
        ])
        let book = Self.book()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            drafts: book,
            describeDraft: { operation in
                guard case .single(let draft) = operation else { return .null }
                return ["amount": .number(draft.amount)]
            },
            fastPath: Self.coffeeFastPath
        )

        await model.send("кофе 1500")
        await model.send("Сколько осталось на кафе?")
        await book.save("draft_1")
        await model.send("А на такси?")

        let texts = transport.calls.map { call in call.last?.content.compactMap { $0["text"]?.stringValue } ?? [] }
        #expect(texts[0] == [
            "<app_context>a</app_context>\n<draft_status>\ndraft_1: made on the phone from the user's message \"кофе 1500\", not by you; not saved yet, items now: [{\"amount\":1500}]\n</draft_status>",
            "Сколько осталось на кафе?",
        ])
        #expect(texts[1] == [
            "<draft_status>\ndraft_1: made on the phone from the user's message \"кофе 1500\", not by you; saved, items now: [{\"amount\":1500}]\n</draft_status>",
            "А на такси?",
        ])
    }

    @Test func aThreadKeepsWhereThePhoneAnswered() async throws {
        let box = ThreadBox()
        let first = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([
                [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            ]), toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            drafts: Self.book(),
            fastPath: Self.coffeeFastPath,
            persistence: box.persistence
        )
        await first.send("Сколько у меня денег?")
        await first.send("кофе 1500")
        let kept = try #require(box.saved)
        #expect(kept.body.local == [AgentThreadSnapshot.LocalExchange(position: 2, question: "кофе 1500", draftId: "draft_1")])

        let book = Self.book()
        let second = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit()),
            context: { "<app_context>a</app_context>" },
            drafts: book,
            fastPath: Self.coffeeFastPath,
            persistence: box.persistence
        )
        await second.restore()
        #expect(second.entries.compactMap(\.question) == ["Сколько у меня денег?", "кофе 1500"])
        #expect(second.entries.count == 4)
        // The phone's draft number is taken: the next draft is draft_2.
        #expect(book.add([]) == "draft_2")
    }

    @Test func aFailedAttestationIsNotSoldAsPro() {
        // The server checks App Attest for Pro too, so Pro would not help.
        #expect(AssistantFailure(AgentServerError.attestation(reason: "unsupported")) == .unavailable)
    }

    @Test func stepsAreNamedAfterTheTools() {
        #expect(AssistantStep(tool: "get_spending_summary") == .spending)
        #expect(AssistantStep(tool: "render_reply") == .composing)
        #expect(AssistantStep(tool: "simulate_loan") == .calculating)
        #expect(AssistantStep(tool: "something_new") == .understanding)
    }
}
