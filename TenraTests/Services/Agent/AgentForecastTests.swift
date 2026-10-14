//
//  AgentForecastTests.swift
//  TenraTests
//
//  `forecast_balance`: today's balance of the everyday accounts, less every occurrence of a
//  subscription before the date (its already generated future occurrence counted once),
//  planned expenses, the cushion and the what-if changes, spread over the days. All amounts
//  are KZT, so no FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentForecastTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    /// Returns the store too: tests must retain it (AccountsViewModel keeps it weakly).
    private static func make() -> (FinanceToolkit, TransactionStore) {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: recurring
        )
        store.categories = [
            CustomCategory(id: "cat_subs", name: "Подписки", colorHex: "#FF2D55", type: .expense),
            CustomCategory(id: "cat_home", name: "Ремонт", colorHex: "#8E8E93", type: .expense),
        ]
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 300_000),
            Account(id: "acc_hidden", name: "Заначка", currency: "KZT", balance: 100_000, includeInBalance: false),
        ]
        recurring.load(series: [
            RecurringSeries(
                id: "rec_netflix", amount: 5_000, currency: "KZT", category: "Подписки", description: "Netflix",
                accountId: "acc_kaspi", frequency: .monthly, startDate: "2026-09-05", kind: .subscription, status: .active
            ),
        ], occurrences: [])
        store.transactions = [
            Transaction(id: "t_repair", date: "2026-11-03", description: "Ремонт", amount: 20_000, currency: "KZT", type: .expense, category: "Ремонт", accountId: "acc_kaspi"),
            // The subscription's generated future occurrence: counted from the series, not twice.
            Transaction(id: "t_netflix", date: "2026-11-05", description: "Netflix", amount: 5_000, currency: "KZT", type: .expense, category: "Подписки", accountId: "acc_kaspi", recurringSeriesId: "rec_netflix"),
            // After the date: not counted.
            Transaction(id: "t_later", date: "2026-11-20", description: "Отпуск", amount: 90_000, currency: "KZT", type: .expense, category: "Ремонт", accountId: "acc_kaspi"),
        ]
        return (FinanceToolkit(store: store, now: { now }), store)
    }

    @Test func theAllowanceIsWhatIsLeftSpreadOverTheDays() async throws {
        let (toolkit, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "forecast_balance", input: [
            "until": "2026-11-10",
            "cushion": 10_000,
            "extra_changes": [["label": "Отложить", "amount": -50_000, "date": "2026-11-01"]],
        ])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["days"] == .number(13))
        // The hidden account is not part of the everyday money.
        #expect(value["start_balance"] == .number(300_000))
        #expect(value.value(atPath: "obligations.0.label") == "Ремонт")
        #expect(value.value(atPath: "obligations.1.label") == "Netflix")
        #expect(value["obligations"]?.arrayValue?.count == 2)
        #expect(value["obligations_total"] == .number(25_000))
        #expect(value["extra_changes_total"] == .number(-50_000))
        #expect(value["free_amount"] == .number(215_000))
        #expect(value["daily_allowance"] == .number(16_538.46))
        #expect(value["series"]?.arrayValue?.count == 14)
        // Spending the allowance every day leaves the cushion.
        #expect(value.value(atPath: "series.13.balance") == .number(10_000.02))
        #expect(value["missing_rates"] == .array([]))
    }

    @Test func theDateMustBeAheadAndTheAccountsKnown() async {
        let (toolkit, store) = Self.make()
        _ = store
        let past = await toolkit.execute(name: "forecast_balance", input: ["until": "2026-10-28"])
        #expect(past.error == "until must be after today.")
        let unknown = await toolkit.execute(name: "forecast_balance", input: ["until": "2026-11-10", "account_ids": ["acc_nope"]])
        #expect(unknown.error == "Unknown account acc_nope.")
        let far = await toolkit.execute(name: "forecast_balance", input: ["until": "2028-01-01"])
        #expect(far.error == "until must be within a year.")
    }
}
