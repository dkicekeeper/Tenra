//
//  AgentReviewTests.swift
//  TenraTests
//
//  The assistant goes through the payments on review (FinanceToolkit+Review):
//  `get_review_queue` lists the captured payments with a guess nobody looked at and counts the
//  screen's questions apart, `draft_review_confirm` files the right ones as one draft, and a
//  confirmation teaches the merchant's category and is taken back whole by Undo.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentReviewTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    private static func payment(_ id: String, merchant: String) -> WalletPayment {
        WalletPayment(id: id, amount: 4_200, currencyCode: "KZT", merchant: merchant, card: "Kaspi Gold", accountId: nil, date: now)
    }

    /// Returns the store too: tests must retain it.
    private static func make() -> (FinanceToolkit, AgentDraftBook, TransactionStore, WalletCaptureStore) {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.categories = [
            CustomCategory(id: "cat_cafe", name: "Кафе", colorHex: "#FF9500", type: .expense),
            CustomCategory(id: "cat_food", name: "Продукты", colorHex: "#34C759", type: .expense),
        ]
        store.accounts = [Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_850)]
        store.transactions = [
            Transaction(id: "t_glovo", date: "2026-10-27", description: "Glovo", amount: 4_200, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            Transaction(id: "t_magnum", date: "2026-10-26", description: "Magnum", amount: 9_800, currency: "KZT", type: .expense, category: "Продукты", accountId: "acc_kaspi"),
            Transaction(id: "t_spotify", date: "2026-10-25", description: "Spotify", amount: 2_990, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
        ]
        store.hasCompletedInitialLoad = true
        let captures = WalletCaptureStore(defaults: defaults)
        captures.record(transactionId: "t_glovo", payment: payment("p1", merchant: "GLOVO ALMATY"), guesses: [.category], now: now)
        captures.record(transactionId: "t_magnum", payment: payment("p2", merchant: "MAGNUM"), guesses: [.category, .account], now: now)
        // A question for the To review screen, not a payment to confirm here.
        captures.record(transactionId: "t_spotify", payment: payment("p3", merchant: "SPOTIFY"), guesses: [], subscriptionSuggestion: "series_spotify", now: now)
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { _ in .series("unused") },
            undo: { _ in }
        ))
        let toolkit = FinanceToolkit(
            store: store, drafts: book, captures: captures, learned: VoiceLearningStore(defaults: defaults), now: { now }
        )
        return (toolkit, book, store, captures)
    }

    @Test func theQueueListsGuessedPaymentsAndCountsTheQuestionsApart() async throws {
        let (toolkit, _, store, _) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "get_review_queue", input: [:])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["total"] == 2)
        #expect(value["questions_on_screen"] == 1)
        #expect(value.value(atPath: "payments.0.transaction_id") == "t_glovo")
        #expect(value.value(atPath: "payments.0.merchant") == "GLOVO ALMATY")
        #expect(value.value(atPath: "payments.0.category") == "Кафе")
        #expect(value.value(atPath: "payments.1.guessed.0") == "account")
    }

    @Test func confirmingAllDraftsEveryPaymentAndNoQuestion() async throws {
        let (toolkit, book, store, captures) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_review_confirm", input: ["all": true])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["count"] == 2)
        #expect(value["left_on_review"] == 0)
        let draft = try #require(book.drafts["draft_1"])
        #expect(draft.operations.count == 2)
        guard case .reviewConfirm(let first)? = draft.operations.first else {
            Issue.record("expected a confirmation")
            return
        }
        #expect(first.id == "t_glovo")
        // Nothing is confirmed before Save.
        #expect(captures.toReview.count == 3)
    }

    @Test func aPaymentThatIsNotOnReviewIsSkipped() async throws {
        let (toolkit, _, store, _) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_review_confirm", input: ["transaction_ids": ["t_magnum", "t_spotify"]])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["count"] == 1)
        #expect(value["left_on_review"] == 1)
        #expect(value.value(atPath: "skipped.0.transaction_id") == "t_spotify")

        let none = await toolkit.execute(name: "draft_review_confirm", input: ["transaction_ids": ["t_spotify"]])
        #expect(none.value == nil)
    }

    @Test func aConfirmationTeachesTheMerchantAndUndoTakesItBack() async throws {
        let (_, _, store, captures) = Self.make()
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let merchants = MerchantCategoryMemory(defaults: defaults)
        let cards = CardAccountMemory(defaults: defaults)
        let categories = CategoriesViewModel(repository: UserDefaultsRepository(userDefaults: defaults))
        categories.transactionStore = store
        let glovo = try #require(store.transactions.first { $0.id == "t_glovo" })

        let undo = try #require(AgentReviewConfirm.confirm(
            glovo, categoriesViewModel: categories, captures: captures, merchants: merchants, cards: cards
        ))
        #expect(captures.capture(forTransactionId: "t_glovo")?.isReviewed == true)
        #expect(merchants.category(forMerchant: "GLOVO ALMATY", in: store.categories)?.id == "cat_cafe")
        #expect(cards.accountId(forCard: "Kaspi Gold") == "acc_kaspi")
        // Looked at already: a second confirmation has nothing to undo.
        #expect(AgentReviewConfirm.confirm(
            glovo, categoriesViewModel: categories, captures: captures, merchants: merchants, cards: cards
        ) == nil)

        AgentReviewConfirm.undo(undo, captures: captures, merchants: merchants, cards: cards)
        #expect(captures.capture(forTransactionId: "t_glovo")?.isReviewed == false)
        #expect(merchants.category(forMerchant: "GLOVO ALMATY", in: store.categories) == nil)
        #expect(cards.accountId(forCard: "Kaspi Gold") == nil)
    }
}
