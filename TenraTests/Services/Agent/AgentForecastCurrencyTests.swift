//
//  AgentForecastCurrencyTests.swift
//  TenraTests
//
//  `forecast_balance` (and "For today", which reads it) with money in other currencies and on
//  deposits: a deposit counts only when the person marked it (`DepositInfo.countsForToday`), and
//  a subscription or a planned expense in dollars on a tenge card is set aside at today's rate.
//
//  @MainActor + .sharedProcessState: the tests seed the process-global CurrencyRateStore.shared
//  (cleared in init).
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct AgentForecastCurrencyTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    init() {
        CurrencyRateStore.shared.clearAll()
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500],
            date: Date(),
            providerName: "test"
        ))
    }

    private static func deposit(countsForToday: Bool) -> DepositInfo {
        DepositInfo(
            bankName: "Bank",
            initialPrincipal: 1_000_000,
            interestRateAnnual: 14,
            interestPostingDay: 1,
            countsForToday: countsForToday
        )
    }

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
            CustomCategory(id: "cat_shop", name: "Покупки", colorHex: "#8E8E93", type: .expense),
        ]
        store.accounts = [
            Account(id: "acc_card", name: "Card", currency: "KZT", balance: 300_000),
            Account(id: "acc_open", name: "Open deposit", currency: "KZT", depositInfo: deposit(countsForToday: true), balance: 1_000_000),
            Account(id: "acc_locked", name: "Term deposit", currency: "KZT", depositInfo: deposit(countsForToday: false), balance: 2_000_000),
        ]
        recurring.load(series: [
            RecurringSeries(
                id: "rec_ai", amount: 20, currency: "USD", category: "Подписки", description: "AI",
                accountId: "acc_card", frequency: .monthly, startDate: "2026-09-10", kind: .subscription, status: .active
            ),
        ], occurrences: [])
        store.transactions = [
            // Dollars on the tenge card, no dollar account: set aside at today's rate.
            Transaction(id: "t_usd", date: "2026-11-03", description: "Headphones", amount: 50, currency: "USD", convertedAmount: 24_000, type: .expense, category: "Покупки", accountId: "acc_card"),
        ]
        return (FinanceToolkit(store: store, now: { now }), store)
    }

    @Test func aMarkedDepositCountsAndForeignPaymentsAreSetAside() async throws {
        let (toolkit, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "forecast_balance", input: ["until": "2026-11-15"])
        let value = try #require(output.value, "\(output.error ?? "")")
        // The card and the deposit marked for today; the term deposit is savings.
        #expect(value["start_balance"] == .number(1_300_000))
        #expect(value.value(atPath: "obligations.0.label") == "Headphones")
        #expect(value.value(atPath: "obligations.0.amount") == .number(25_000))
        #expect(value.value(atPath: "obligations.1.label") == "AI")
        #expect(value.value(atPath: "obligations.1.amount") == .number(10_000))
        #expect(value["obligations_total"] == .number(35_000))
        #expect(value["missing_rates"] == .array([]))
    }

    @Test func whichAccountsCountForToday() {
        #expect(Account(name: "Card", currency: "KZT").countsForToday)
        #expect(!Account(name: "Stash", currency: "KZT", includeInBalance: false).countsForToday)
        #expect(!Account(name: "Term", currency: "KZT", depositInfo: Self.deposit(countsForToday: false)).countsForToday)
        #expect(Account(name: "Open", currency: "KZT", depositInfo: Self.deposit(countsForToday: true)).countsForToday)
    }

    @Test func aDepositSavedBeforeTheSettingDoesNotCount() throws {
        let saved = try JSONEncoder().encode(Self.deposit(countsForToday: true))
        var json = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(json["countsForToday"] as? Bool == true)
        json.removeValue(forKey: "countsForToday")
        let old = try JSONDecoder().decode(DepositInfo.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!old.countsForToday)
    }
}
