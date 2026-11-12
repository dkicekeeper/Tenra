//
//  AgentChangeTests.swift
//  TenraTests
//
//  The assistant changes what is saved (FinanceToolkit+Changes): `draft_transaction_edit`
//  drafts one income or expense with new fields and keeps what it was, and
//  `draft_transaction_delete` drafts up to twenty deletions and skips what it may not touch
//  (a transfer). Nothing is written before Save. Amounts are KZT: no FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentChangeTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    /// Returns the store too: tests must retain it.
    private static func make() -> (FinanceToolkit, AgentDraftBook, TransactionStore) {
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
            CustomCategory(id: "cat_salary", name: "Зарплата", colorHex: "#5856D6", type: .income),
        ]
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_850),
            Account(id: "acc_halyk", name: "Halyk", currency: "KZT", balance: 50_000),
        ]
        store.transactions = [
            Transaction(id: "t_glovo", date: "2026-10-27", description: "Glovo", amount: 4_200, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            Transaction(id: "t_coffee", date: "2026-10-26", description: "Coffee Boom", amount: 1_500, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            Transaction(
                id: "t_move", date: "2026-10-25", description: "", amount: 20_000, currency: "KZT", type: .internalTransfer,
                category: TransactionType.transferCategoryName, accountId: "acc_kaspi", targetAccountId: "acc_halyk"
            ),
        ]
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { _ in .series("unused") },
            undo: { _ in }
        ))
        let toolkit = FinanceToolkit(store: store, drafts: book, learned: VoiceLearningStore(defaults: defaults), now: { now })
        return (toolkit, book, store)
    }

    @Test func anEditKeepsWhatWasAndDraftsWhatBecomes() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_transaction_edit", input: [
            "transaction_id": "t_glovo", "amount": 4_700, "category": "cat_food", "date": .null, "note": .null,
        ])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["draft_id"] == "draft_1")
        #expect(value["saved"] == false)
        #expect(value.value(atPath: "before.category") == "Кафе")
        #expect(value.value(atPath: "after.category") == "Продукты")
        #expect(value.value(atPath: "after.amount") == 4_700)
        #expect(value.value(atPath: "after.date") == "2026-10-27")

        let draft = try #require(book.drafts["draft_1"])
        guard case .transactionEdit(let edit)? = draft.operations.first else {
            Issue.record("expected an edit")
            return
        }
        #expect(edit.before.amount == 4_200)
        #expect(edit.after.amount == 4_700)
        #expect(edit.after.id == "t_glovo")
        #expect(edit.after.accountId == "acc_kaspi")
        // Nothing is written before Save.
        #expect(store.transactions.first { $0.id == "t_glovo" }?.amount == 4_200)
    }

    @Test func anEditThatChangesNothingOrBreaksARuleIsRefused() async {
        let (toolkit, book, store) = Self.make()
        _ = store
        let same = await toolkit.execute(name: "draft_transaction_edit", input: [
            "transaction_id": "t_glovo", "amount": .null, "category": "Кафе", "date": .null, "note": .null,
        ])
        #expect(same.error?.contains("Nothing changes") == true)
        let future = await toolkit.execute(name: "draft_transaction_edit", input: [
            "transaction_id": "t_glovo", "amount": .null, "category": .null, "date": "2026-11-05", "note": .null,
        ])
        #expect(future.error?.contains("future") == true)
        let income = await toolkit.execute(name: "draft_transaction_edit", input: [
            "transaction_id": "t_glovo", "amount": .null, "category": "cat_salary", "date": .null, "note": .null,
        ])
        #expect(income.error?.contains("Unknown expense category") == true)
        let transfer = await toolkit.execute(name: "draft_transaction_edit", input: [
            "transaction_id": "t_move", "amount": 25_000, "category": .null, "date": .null, "note": .null,
        ])
        #expect(transfer.error?.contains("History") == true)
        let unknown = await toolkit.execute(name: "draft_transaction_edit", input: [
            "transaction_id": "nope", "amount": 1, "category": .null, "date": .null, "note": .null,
        ])
        #expect(unknown.error?.contains("Unknown transaction") == true)
        #expect(book.drafts.isEmpty)
    }

    @Test func aDeletionListsItsRecordsAndSkipsATransfer() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_transaction_delete", input: [
            "transaction_ids": ["t_glovo", "t_coffee", "t_glovo", "t_move"],
        ])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["count"] == 2)
        #expect(value.value(atPath: "items.1.merchant") == "Coffee Boom")
        #expect(value.value(atPath: "skipped.0.transaction_id") == "t_move")
        let draft = try #require(book.drafts["draft_1"])
        #expect(draft.operations.count == 2)
        #expect(store.transactions.count == 3)

        let tooMany = await toolkit.execute(name: "draft_transaction_delete", input: [
            "transaction_ids": .array((0..<21).map { JSONValue.string("t\($0)") }),
        ])
        #expect(tooMany.error?.contains("At most 20") == true)
    }

    @Test func aSubscriptionPausesOnlyWhileItRuns() async throws {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: BalanceCoordinator(repository: repo), recurringStore: recurring)
        recurring.load(series: [
            RecurringSeries(
                id: "rec_spotify", amount: 2_990, currency: "KZT", category: "Подписки", description: "Spotify",
                accountId: "acc_kaspi", frequency: .monthly, startDate: "2026-09-14", kind: .subscription, status: .active
            ),
        ], occurrences: [])
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(save: { _ in .series("unused") }, undo: { _ in }))
        let toolkit = FinanceToolkit(store: store, drafts: book, learned: VoiceLearningStore(defaults: defaults), now: { Self.now })

        let output = await toolkit.execute(name: "draft_subscription_state", input: ["subscription": "spotify", "action": "pause"])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["subscription_id"] == "rec_spotify")
        guard case .subscriptionState(let series, let pause)? = book.drafts["draft_1"]?.operations.first else {
            Issue.record("expected a pause")
            return
        }
        #expect(pause)
        #expect(series.id == "rec_spotify")

        let resume = await toolkit.execute(name: "draft_subscription_state", input: ["subscription": "rec_spotify", "action": "resume"])
        #expect(resume.error?.contains("not paused") == true)
        let unknown = await toolkit.execute(name: "draft_subscription_state", input: ["subscription": "Hulu", "action": "pause"])
        #expect(unknown.error?.contains("Unknown subscription") == true)
    }

    @Test func loansAndDepositsAreListedEvenWhenThereAreNone() async throws {
        let (toolkit, _, store) = Self.make()
        _ = store
        let loansOutput = await toolkit.execute(name: "get_loans", input: [:])
        let loans = try #require(loansOutput.value)
        #expect(loans["loans"] == .array([]))
        let depositsOutput = await toolkit.execute(name: "get_deposits", input: [:])
        let deposits = try #require(depositsOutput.value)
        #expect(deposits["deposits"] == .array([]))
    }

    @Test func recategorizeMovesAMerchantsRecordsInOneDraft() async throws {
        let (toolkit, book, store) = Self.make()
        store.transactions.append(
            Transaction(id: "t_glovo2", date: "2026-09-12", description: "GLOVO KZ", amount: 3_100, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi")
        )
        let output = await toolkit.execute(name: "draft_recategorize", input: [
            "merchant": "glovo", "category": "cat_food", "from": .null, "to": .null,
        ])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["count"] == 2)
        #expect(value["category"] == "Продукты")
        let draft = try #require(book.drafts["draft_1"])
        #expect(draft.operations.count == 2)
        for operation in draft.operations {
            guard case .transactionEdit(let edit) = operation else {
                Issue.record("expected edits")
                return
            }
            #expect(edit.before.category == "Кафе")
            #expect(edit.after.category == "Продукты")
            #expect(edit.after.amount == edit.before.amount)
        }

        // A period narrows it; nothing there is said so.
        let september = await toolkit.execute(name: "draft_recategorize", input: [
            "merchant": "glovo", "category": "cat_food", "from": "2026-09-01", "to": "2026-09-30",
        ])
        #expect(september.value?["count"] == 1)
        let none = await toolkit.execute(name: "draft_recategorize", input: [
            "merchant": "netflix", "category": "cat_food", "from": .null, "to": .null,
        ])
        #expect(none.error?.contains("No expense records") == true)
    }
}
