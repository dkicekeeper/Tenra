//
//  FinanceToolkitTests.swift
//  TenraTests
//
//  The assistant's read tools over a seeded store. Every figure must follow the app's rules:
//  `summaryContribution` decides what counts as income and expense, future-dated operations
//  are excluded, transfers never count. All amounts are KZT, so no FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct FinanceToolkitTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    private static func tx(_ id: String, _ date: String, _ amount: Double, _ type: TransactionType, _ category: String, _ description: String = "", account: String = "acc_kaspi") -> Transaction {
        Transaction(id: id, date: date, description: description, amount: amount, currency: "KZT", type: type, category: category, accountId: account)
    }

    private static let transactions: [Transaction] = [
        tx("t1", "2026-10-05", 1_500, .expense, "Кафе", "Coffee Boom"),
        tx("t2", "2026-10-20", 2_500, .expense, "Кафе", "Coffee Boom"),
        tx("t3", "2026-10-10", 8_000, .expense, "Продукты", "Magnum"),
        tx("t4", "2026-10-10", 650_000, .income, "Зарплата", "Работа"),
        tx("t5", "2026-10-11", 100_000, .internalTransfer, "Перевод", "На депозит"),
        tx("t6", "2026-10-30", 9_999, .expense, "Кафе", "Coffee Boom"),
        tx("t7", "2026-09-15", 4_000, .expense, "Кафе", "Coffee Boom"),
    ]

    /// Returns the store too: tests must retain it (AccountsViewModel keeps it weakly).
    private static func make() -> (FinanceToolkit, TransactionStore) {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.categories = [
            CustomCategory(id: "cat_cafe", name: "Кафе", colorHex: "#FF9500", type: .expense, budgetAmount: 150_000),
            CustomCategory(id: "cat_food", name: "Продукты", colorHex: "#34C759", type: .expense),
            CustomCategory(id: "cat_salary", name: "Зарплата", colorHex: "#5856D6", type: .income),
        ]
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_850),
            Account(id: "acc_hidden", name: "Заначка", currency: "KZT", balance: 100_000, includeInBalance: false),
        ]
        store.transactions = transactions
        return (FinanceToolkit(store: store, now: { now }), store)
    }

    private static func run(_ name: String, _ input: JSONValue) async -> (AgentToolOutput, TransactionStore) {
        let (toolkit, store) = make()
        return (await toolkit.execute(name: name, input: input), store)
    }

    @Test func spendingFollowsTheAppRules() async throws {
        let (output, store) = await Self.run("get_spending_summary", ["from": "2026-10-01", "to": "2026-10-31", "type": "expense", "group_by": "category"])
        _ = store
        let value = try #require(output.value, "\(output.error ?? "")")
        // Income, the transfer and the future-dated cafe bill are all left out.
        #expect(value["total"] == .number(12_000))
        #expect(value["count"] == .number(3))
        #expect(value.value(atPath: "groups.0.key") == "cat_food")
        #expect(value.value(atPath: "groups.1.key") == "cat_cafe")
        #expect(value.value(atPath: "groups.1.total") == .number(4_000))
        #expect(value.value(atPath: "groups.1.label") == "Кафе")
    }

    @Test func categoryFilterTakesIds() async throws {
        let (output, store) = await Self.run("get_spending_summary", ["from": "2026-10-01", "to": "2026-10-31", "type": "expense", "category_ids": ["cat_cafe"]])
        _ = store
        #expect(output.value?["total"] == .number(4_000))

        let (unknown, other) = await Self.run("get_spending_summary", ["from": "2026-10-01", "to": "2026-10-31", "type": "expense", "category_ids": ["cat_nope"]])
        _ = other
        #expect(unknown.error?.contains("Unknown category") == true)
    }

    @Test func incomeIsSeparate() async {
        let (output, store) = await Self.run("get_spending_summary", ["from": "2026-10-01", "to": "2026-10-31", "type": "income"])
        _ = store
        #expect(output.value?["total"] == .number(650_000))
    }

    @Test func monthsGroupInOrder() async throws {
        let (output, store) = await Self.run("get_spending_summary", ["from": "2026-09-01", "to": "2026-10-31", "type": "expense", "group_by": "month"])
        _ = store
        let value = try #require(output.value)
        #expect(value.value(atPath: "groups.0.key") == "2026-09")
        #expect(value.value(atPath: "groups.0.total") == .number(4_000))
        #expect(value.value(atPath: "groups.1.key") == "2026-10")
        #expect(value.value(atPath: "groups.1.total") == .number(12_000))
    }

    @Test func comparesPeriods() async throws {
        let (output, store) = await Self.run("compare_periods", [
            "type": "expense",
            "current": ["from": "2026-10-01", "to": "2026-10-31"],
            "previous": ["from": "2026-09-01", "to": "2026-09-30"],
            "group_by": "category",
        ])
        _ = store
        let value = try #require(output.value)
        #expect(value.value(atPath: "current.total") == .number(12_000))
        #expect(value.value(atPath: "previous.total") == .number(4_000))
        #expect(value["change"] == .number(8_000))
        #expect(value["change_percent"] == .number(200))
        #expect(value.value(atPath: "groups.0.key") == "cat_food")
    }

    @Test func searchFindsAndSorts() async throws {
        let (byText, store) = await Self.run("search_transactions", ["query": "coffee", "type": "any", "sort": "newest", "limit": 10])
        _ = store
        let found = try #require(byText.value)
        #expect(found["count_total"] == .number(3)) // the future-dated bill is not a past operation
        #expect(found.value(atPath: "items.0.date") == "2026-10-20")
        #expect(found.value(atPath: "items.0.category_id") == "cat_cafe")
        #expect(found.value(atPath: "items.0.account") == "Kaspi Gold")

        let (largest, other) = await Self.run("search_transactions", ["type": "expense", "sort": "largest", "limit": 1])
        _ = other
        #expect(largest.value?.value(atPath: "items.0.amount_base") == .number(8_000))
        #expect(largest.value?.value(atPath: "items.1") == nil)
    }

    @Test func accountsTotalSkipsExcludedAccounts() async throws {
        let (output, store) = await Self.run("get_accounts", [:])
        _ = store
        let value = try #require(output.value)
        #expect(value["total_base"] == .number(260_850))
        #expect(value.value(atPath: "accounts.1.counted_in_total") == .bool(false))
        #expect(value.value(atPath: "accounts.0.kind") == "regular")
    }

    @Test func budgetsListCategoriesWithALimit() async throws {
        let (output, store) = await Self.run("get_budgets", [:])
        _ = store
        let value = try #require(output.value)
        #expect(value.value(atPath: "budgets.0.category_id") == "cat_cafe")
        #expect(value.value(atPath: "budgets.0.limit") == .number(150_000))
        #expect(value.value(atPath: "budgets.1") == nil)
    }

    @Test func invalidInputIsReportedToTheModel() async {
        let (badDates, store) = await Self.run("get_spending_summary", ["from": "28.10.2026", "to": "2026-10-31", "type": "expense"])
        _ = store
        #expect(badDates.error == "Dates must be YYYY-MM-DD.")

        let (badType, other) = await Self.run("get_spending_summary", ["from": "2026-10-01", "to": "2026-10-31", "type": "transfer"])
        _ = other
        #expect(badType.error == "type must be expense or income.")
    }

    @Test func laterPhaseAndUnknownToolsAnswerWithoutCrashing() async {
        let (draft, store) = await Self.run("forecast_balance", ["until": "2026-11-10"])
        _ = store
        #expect(draft.error?.contains("not available") == true)
        // Without a draft book (not wired) drafting answers the same way.
        let (unwired, kept) = await Self.run("draft_transactions", ["items": []])
        _ = kept
        #expect(unwired.error?.contains("not available") == true)

        let (unknown, other) = await Self.run("delete_everything", [:])
        _ = other
        #expect(unknown.error == "Unknown tool delete_everything.")
    }
}
