//
//  AgentDraftTests.swift
//  TenraTests
//
//  The assistant's drafts: `draft_transactions` resolves the model's operations the way the
//  voice and Siri paths do (ids or names, a guessed account marked as guessed, transfers
//  between two regular accounts, what cannot be drafted skipped with a reason), `draft_budget`
//  keeps the previous limit, and the draft book saves a draft whole or not at all and undoes
//  it. All amounts are KZT, so no FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentDraftTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    /// Records what the book asked to write and delete; fails the save of `failOn`.
    @MainActor
    private final class FakeWriter {
        var saved: [AgentDraftOperation] = []
        var deleted: [String] = []
        var failOn: Int?

        var writer: AgentDraftBook.Writer {
            AgentDraftBook.Writer(
                save: { operation in
                    if self.failOn == self.saved.count { throw FinanceToolError(message: "disk full") }
                    self.saved.append(operation)
                    return .transaction(Transaction(id: "tx\(self.saved.count)", date: "2026-10-28", description: "", amount: 1, currency: "KZT", type: .expense, category: ""))
                },
                undo: { record in
                    if case .transaction(let transaction) = record { self.deleted.append(transaction.id) }
                }
            )
        }
    }

    /// Returns the store too: tests must retain it (AccountsViewModel keeps it weakly).
    /// `writer` is optional because a default argument is built outside the main actor.
    private static func make(writer: FakeWriter? = nil) -> (FinanceToolkit, AgentDraftBook, TransactionStore) {
        let writer = writer ?? FakeWriter()
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.categories = [
            CustomCategory(id: "cat_cafe", name: "Кафе", colorHex: "#FF9500", type: .expense, budgetAmount: 80_000),
            CustomCategory(id: "cat_taxi", name: "Такси", colorHex: "#FFCC00", type: .expense),
            CustomCategory(id: "cat_salary", name: "Зарплата", colorHex: "#5856D6", type: .income),
        ]
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_850),
            Account(id: "acc_halyk", name: "Halyk", currency: "KZT", balance: 50_000),
        ]
        let book = AgentDraftBook(writer: writer.writer)
        let toolkit = FinanceToolkit(store: store, drafts: book, learned: VoiceLearningStore(defaults: defaults), now: { now })
        return (toolkit, book, store)
    }

    private static func item(
        _ amount: Double,
        type: String = "expense",
        category: String? = nil,
        account: String? = nil,
        to: String? = nil,
        date: String? = nil,
        note: String? = nil
    ) -> JSONValue {
        [
            "type": .string(type),
            "amount": .number(amount),
            "currency": .null,
            "category": category.map(JSONValue.string) ?? .null,
            "account": account.map(JSONValue.string) ?? .null,
            "to_account": to.map(JSONValue.string) ?? .null,
            "date": date.map(JSONValue.string) ?? .null,
            "note": note.map(JSONValue.string) ?? .null,
        ]
    }

    // MARK: - draft_transactions

    @Test func idsResolveAndTheDraftIsFiled() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_transactions", input: ["items": [
            Self.item(1_500, category: "cat_cafe", account: "acc_kaspi", date: "2026-10-27", note: "Кофе"),
        ]])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["draft_id"] == "draft_1")
        #expect(value["saved"] == false)
        #expect(value.value(atPath: "items.0.category") == "Кафе")
        #expect(value.value(atPath: "items.0.category_id") == "cat_cafe")
        #expect(value.value(atPath: "items.0.account") == "Kaspi Gold")
        #expect(value.value(atPath: "items.0.date") == "2026-10-27")
        #expect(value.value(atPath: "items.0.note") == "Кофе")
        #expect(value["items"]?.value(atPath: "0.guessed") == .array([]))

        let draft = try #require(book.drafts["draft_1"])
        guard case .single(let operation)? = draft.operations.first else {
            Issue.record("expected an expense")
            return
        }
        #expect(operation.amount == 1_500)
        #expect(operation.categoryName == "Кафе")
        #expect(operation.accountId == "acc_kaspi")
        #expect(book.states["draft_1"] == .pending)
    }

    @Test func namesWorkAndAGuessedAccountIsMarked() async throws {
        let (toolkit, _, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_transactions", input: ["items": [
            Self.item(2_300, category: "такси"),
            Self.item(650_000, type: "income", category: "Зарплата", account: "halyk"),
        ]])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value.value(atPath: "items.0.category") == "Такси")
        #expect(value.value(atPath: "items.0.guessed.0") == "account")
        // No date: today.
        #expect(value.value(atPath: "items.0.date") == "2026-10-28")
        #expect(value.value(atPath: "items.1.type") == "income")
        #expect(value.value(atPath: "items.1.account_id") == "acc_halyk")
    }

    @Test func aTransferNeedsTwoDifferentAccounts() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_transactions", input: ["items": [
            Self.item(20_000, type: "transfer", account: "acc_kaspi", to: "acc_halyk"),
            Self.item(5_000, type: "transfer", account: "acc_kaspi", to: "acc_kaspi"),
        ]])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value.value(atPath: "items.0.to_account") == "Halyk")
        #expect(value.value(atPath: "skipped.0.index") == .number(1))
        guard case .transfer(let transfer)? = book.drafts["draft_1"]?.operations.first else {
            Issue.record("expected a transfer")
            return
        }
        #expect(transfer.fromAccountId == "acc_kaspi")
        #expect(transfer.toAccountId == "acc_halyk")
        #expect(transfer.conversion.targetAmount == 20_000)
        #expect(transfer.conversion.convertedAmount == nil)
    }

    @Test func nothingDraftableIsAnError() async {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_transactions", input: ["items": [
            Self.item(0, category: "cat_cafe"),
            Self.item(100, type: "refund"),
        ]])
        #expect(output.error?.contains("amount must be positive") == true)
        #expect(output.error?.contains("type must be expense, income or transfer") == true)
        #expect(book.drafts.isEmpty)
    }

    @Test func aBudgetDraftKeepsThePreviousLimit() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_budget", input: ["category": "кафе", "amount": 100_000, "period": "monthly"])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["category_id"] == "cat_cafe")
        #expect(value["previous_limit"] == .number(80_000))
        #expect(value["period"] == "monthly")
        #expect(book.drafts["draft_1"]?.operations == [.budget(AgentBudgetDraft(
            categoryId: "cat_cafe", amount: 100_000, period: .monthly, previousAmount: 80_000, previousPeriod: .monthly
        ))])

        let income = await toolkit.execute(name: "draft_budget", input: ["category": "cat_salary", "amount": 1, "period": "monthly"])
        #expect(income.error?.contains("Unknown expense category") == true)
        let badPeriod = await toolkit.execute(name: "draft_budget", input: ["category": "cat_taxi", "amount": 1, "period": "daily"])
        #expect(badPeriod.error == "period must be weekly, monthly or yearly.")
    }

    // MARK: - The book

    @Test func savingWritesEveryOperationAndUndoDeletesThem() async {
        let fake = FakeWriter()
        let (toolkit, book, store) = Self.make(writer: fake)
        _ = store
        _ = await toolkit.execute(name: "draft_transactions", input: ["items": [
            Self.item(1_500, category: "cat_cafe", account: "acc_kaspi"),
            Self.item(2_300, category: "cat_taxi", account: "acc_kaspi"),
        ]])

        await book.save("draft_1")
        #expect(fake.saved.count == 2)
        guard case .saved(let records)? = book.states["draft_1"] else {
            Issue.record("expected saved")
            return
        }
        #expect(records.count == 2)

        // Saving twice writes nothing more.
        await book.save("draft_1")
        #expect(fake.saved.count == 2)

        await book.undo("draft_1")
        #expect(fake.deleted == ["tx2", "tx1"])
        #expect(book.states["draft_1"] == .undone)
    }

    @Test func aFailedSaveLeavesNothingBehind() async {
        let fake = FakeWriter()
        fake.failOn = 1
        let (toolkit, book, store) = Self.make(writer: fake)
        _ = store
        _ = await toolkit.execute(name: "draft_transactions", input: ["items": [
            Self.item(1_500, category: "cat_cafe", account: "acc_kaspi"),
            Self.item(2_300, category: "cat_taxi", account: "acc_kaspi"),
        ]])

        await book.save("draft_1")
        #expect(book.states["draft_1"] == .failed)
        #expect(fake.deleted == ["tx1"])

        // Try again once the problem is gone.
        fake.failOn = nil
        await book.save("draft_1")
        #expect(fake.saved.count == 3)
        if case .saved? = book.states["draft_1"] {} else { Issue.record("expected saved after retry") }
    }

    @Test func aNewChatClearsTheDrafts() {
        let book = AgentDraftBook(writer: FakeWriter().writer)
        #expect(book.add([]) == "draft_1")
        book.clear()
        #expect(book.drafts.isEmpty)
        #expect(book.add([]) == "draft_1")
    }
}
