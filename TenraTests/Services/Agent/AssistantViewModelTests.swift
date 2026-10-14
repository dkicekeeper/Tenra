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

    @Test func draftsNumberOnFromAKeptThread() {
        let results: [String: JSONValue] = ["r1": ["draft_id": "draft_2"], "r2": ["draft_id": "draft_7"], "r3": ["total": 1]]
        #expect(AssistantViewModel.lastDraftNumber(in: results) == 7)
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
