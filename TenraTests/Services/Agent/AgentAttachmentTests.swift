//
//  AgentAttachmentTests.swift
//  TenraTests
//
//  Attachments in the assistant's chat: the summary card's figures (a statement's rows, period,
//  totals in its main currency, expenses by suggested category), the <attachment_result> the
//  model sees with the next question and only then, and the review that spends one free answer
//  once. Invented rows; no statement is in the repo.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentAttachmentTests {

    private static func row(_ id: String, _ amount: Double, _ type: TransactionType = .expense, currency: String = "KZT", date: String) -> Transaction {
        Transaction(id: id, date: date, description: "Shop \(id)", amount: amount, currency: currency, type: type, category: "")
    }

    private static func statement() -> StatementReview {
        let outcome = ImportOutcome(
            csvFile: CSVFile(headers: [], rows: [], preview: []),
            statement: ParsedStatement(
                transactions: [],
                skipped: [SkippedRow(rowIndex: 4, cells: [], reason: "import.skip.noDate")],
                resolvedRoles: nil
            ),
            intelligenceStatus: .notEnabled
        )
        return StatementReview(
            outcome: outcome,
            transactions: [
                row("t1", 1500, date: "2026-10-03"),
                row("t2", 2300, date: "2026-10-01"),
                row("t3", 12000, date: "2026-10-20"),
                row("t4", 400_000, .income, date: "2026-10-10"),
                row("t5", 20, currency: "USD", date: "2026-10-12"),
            ],
            suggestedCategories: ["t1": "Кафе", "t2": "Такси", "t3": "Кафе", "t4": "Зарплата"],
            uncheckedMoves: ["t2": .cashWithdrawal],
            transferEligibleIds: [],
            statementAccountId: "acc_kaspi",
            subcategoryHistory: CategorySuggestionService.SubcategoryIndex(),
            transferHistory: ImportTransferHistory.Index()
        )
    }

    @Test func aStatementSumsUpInItsMainCurrency() {
        let summary = AgentAttachmentSummary.statement(Self.statement(), accountName: "Kaspi Gold")

        #expect(summary.kind == .statement)
        #expect(summary.title == "Kaspi Gold")
        #expect(summary.count == 5)
        #expect(summary.skipped == 1)
        #expect(summary.firstDate == "2026-10-01")
        #expect(summary.lastDate == "2026-10-20")
        #expect(summary.expenses == AgentAttachmentSummary.Total(amount: 15_800, currency: "KZT"))
        #expect(summary.income == AgentAttachmentSummary.Total(amount: 400_000, currency: "KZT"))
        #expect(summary.uncategorized == 1)
        #expect(summary.moves == 1)
        #expect(summary.byCategory == [
            AgentAttachmentSummary.CategoryTotal(category: "Кафе", amount: 13_500),
            AgentAttachmentSummary.CategoryTotal(category: "Такси", amount: 2300),
        ])
    }

    @Test func theModelSeesFiguresOnly() {
        let text = AgentAttachmentSummary.statement(Self.statement(), accountName: "Kaspi Gold").modelText
        #expect(text.hasPrefix("<attachment_result>\n"))
        #expect(text.hasSuffix("\n</attachment_result>"))
        #expect(text.contains("\"rows\":5"))
        #expect(text.contains("\"from\":\"2026-10-01\""))
        #expect(text.contains("\"saved\":false"))
        // No account name and no merchants from the document.
        #expect(!text.contains("Kaspi"))
        #expect(!text.contains("Shop"))
    }

    @Test func aReceiptIsItsTotal() {
        let summary = AgentAttachmentSummary.receipt(ReceiptDraft(merchant: "Magnum", total: 12_450, currency: nil, date: "2026-10-13"), baseCurrency: "KZT")
        #expect(summary.kind == .receipt)
        #expect(summary.title == "Magnum")
        #expect(summary.expenses == AgentAttachmentSummary.Total(amount: 12_450, currency: "KZT"))
        #expect(summary.firstDate == "2026-10-13")
        #expect(!summary.modelText.contains("Magnum"))
    }

    // MARK: - In the thread

    @MainActor
    private final class UsageBox {
        var usage = AssistantUsage()
        var isPro = false
        func access(now: Date) -> AssistantViewModel.Access {
            AssistantViewModel.Access(isPro: { self.isPro }, loadUsage: { self.usage }, saveUsage: { self.usage = $0 }, now: { now })
        }
    }

    @Test func theSummaryGoesWithTheNextQuestionOnly() async {
        let transport = ScriptedTransport([
            [AgentScript.done([AgentScript.render("toolu_1", source: "none")])],
            [AgentScript.done([AgentScript.render("toolu_2", source: "none")])],
        ])
        let model = AssistantViewModel(conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()), context: { "<app_context>a</app_context>" })
        let summary = AgentAttachmentSummary.statement(Self.statement(), accountName: nil)

        model.attach(.statement(Self.statement()), summary: summary)
        #expect(model.entries.map(\.content) == [.attachment(summary)])
        #expect(model.suggestions == [String(localized: "assistant.attachment.analyze")])
        if case .statement? = model.attachment(for: model.entries[0].id) {} else { Issue.record("expected the statement kept for its review") }

        await model.send("Разбери эту выписку")
        await model.send("А что с такси?")

        let texts = transport.calls.map { call in call.last?.content.compactMap { $0["text"]?.stringValue } ?? [] }
        #expect(texts[0] == ["<app_context>a</app_context>", summary.modelText, "Разбери эту выписку"])
        #expect(texts[1] == ["А что с такси?"])
    }

    @Test func aReviewSpendsOneFreeAnswerOnce() {
        let box = UsageBox()
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit()),
            context: { "" },
            access: box.access(now: Date(timeIntervalSince1970: 1_800_000_000))
        )
        let draft = ReceiptDraft(merchant: "Magnum", total: 12_450, currency: "KZT", date: nil)
        model.attach(.receipt(draft), summary: .receipt(draft, baseCurrency: "KZT"))
        let id = model.entries[0].id

        #expect(model.payForReview(of: id))
        #expect(model.payForReview(of: id))
        #expect(box.usage.trialUsed == 1)

        // With none left, a new attachment's review offers Pro; Pro opens it for nothing.
        box.usage.trialUsed = PremiumConfig.Assistant.trialActions
        model.attach(.receipt(draft), summary: .receipt(draft, baseCurrency: "KZT"))
        let next = model.entries[1].id
        #expect(!model.payForReview(of: next))
        box.isPro = true
        #expect(model.payForReview(of: next))
        #expect(box.usage.trialUsed == PremiumConfig.Assistant.trialActions)
    }
}
