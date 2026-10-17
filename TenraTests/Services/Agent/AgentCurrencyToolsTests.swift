//
//  AgentCurrencyToolsTests.swift
//  TenraTests
//
//  The assistant's tools with amounts in other currencies: each one is converted to the base
//  currency with the app's rates (a `_base` field, and in every total), a rate the cache lacks
//  is loaded first, and a currency still without one is listed in `missing_rates`, never
//  counted as zero. `convert_currency` answers "what is the dollar rate". Ten said it had no
//  exchange rates and left a dollar subscription out of the monthly total.
//
//  @MainActor + .sharedProcessState: conversion reads the process-global CurrencyRateStore,
//  seeded per test and cleared in init (CLAUDE.md "Testing").
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct AgentCurrencyToolsTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    init() {
        CurrencyRateStore.shared.clearAll()
        Self.seed([:])
    }

    /// Tenge per unit: USD always, plus `extra`.
    private static func seed(_ extra: [String: Double]) {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: extra.merging(["USD": 480]) { own, _ in own },
            date: Date(),
            providerName: "test"
        ))
    }

    /// Stands in for the network: records what the toolkit asked to load and answers with
    /// `answers`, if any.
    private final class RateLoader {
        var asked: [Set<String>] = []
        var answers: [String: Double] = [:]
    }

    private static func subscription(_ id: String, _ amount: Decimal, _ currency: String) -> RecurringSeries {
        RecurringSeries(
            id: id, amount: amount, currency: currency, category: "Подписки", description: id,
            accountId: "acc_kaspi", frequency: .monthly, startDate: "2026-09-05", kind: .subscription, status: .active
        )
    }

    /// Returns the store too: tests must retain it (AccountsViewModel keeps it weakly).
    private static func make(_ series: [RecurringSeries] = [], loader: RateLoader = RateLoader()) -> (FinanceToolkit, TransactionStore) {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: recurring
        )
        store.categories = [CustomCategory(id: "cat_subs", name: "Подписки", colorHex: "#FF2D55", type: .expense)]
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 300_000),
            Account(id: "acc_usd", name: "Freedom USD", currency: "USD", balance: 100),
        ]
        recurring.load(series: series, occurrences: [])
        let toolkit = FinanceToolkit(store: store, now: { now }, loadRates: { currencies in
            loader.asked.append(currencies)
            if !loader.answers.isEmpty { Self.seed(loader.answers) }
        })
        return (toolkit, store)
    }

    private static func item(_ id: String, in value: JSONValue) -> JSONValue? {
        value["items"]?.arrayValue?.first { $0["id"] == .string(id) }
    }

    @Test func aDollarSubscriptionCountsThroughTheRate() async throws {
        let loader = RateLoader()
        let (toolkit, store) = Self.make([
            Self.subscription("Netflix", 5_000, "KZT"),
            Self.subscription("ChatGPT", 20, "USD"),
        ], loader: loader)
        _ = store
        let output = await toolkit.execute(name: "list_recurring", input: ["kind": "subscription", "active_only": true])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["subscriptions_monthly_total_base"] == .number(14_600))
        #expect(Self.item("ChatGPT", in: value)?["amount"] == .number(20))
        #expect(Self.item("ChatGPT", in: value)?["amount_base"] == .number(9_600))
        #expect(Self.item("ChatGPT", in: value)?["monthly_base"] == .number(9_600))
        #expect(Self.item("Netflix", in: value)?["amount_base"] == .number(5_000))
        #expect(value["missing_rates"] == .array([]))
        // The rate was in the cache: nothing to load.
        #expect(loader.asked.isEmpty)
    }

    @Test func aRateTheCacheLacksIsLoadedFirst() async throws {
        let loader = RateLoader()
        loader.answers = ["EUR": 520]
        let (toolkit, store) = Self.make([
            Self.subscription("Netflix", 5_000, "KZT"),
            Self.subscription("Figma", 10, "EUR"),
        ], loader: loader)
        _ = store
        let output = await toolkit.execute(name: "list_recurring", input: ["kind": "subscription", "active_only": true])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(loader.asked == [["EUR", "KZT"]])
        #expect(value["subscriptions_monthly_total_base"] == .number(10_200))
        #expect(Self.item("Figma", in: value)?["amount_base"] == .number(5_200))
        #expect(value["missing_rates"] == .array([]))
    }

    @Test func aCurrencyWithoutARateIsListedNotCountedAsZero() async throws {
        let (toolkit, store) = Self.make([
            Self.subscription("Netflix", 5_000, "KZT"),
            Self.subscription("Local", 10, "ZZZ"),
        ])
        _ = store
        let output = await toolkit.execute(name: "list_recurring", input: ["kind": "subscription", "active_only": true])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["subscriptions_monthly_total_base"] == .number(5_000))
        #expect(Self.item("Local", in: value)?["amount_base"] == .null)
        #expect(value["missing_rates"] == .array(["ZZZ"]))
    }

    @Test func aDollarAccountCarriesItsTenge() async throws {
        let (toolkit, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "get_accounts", input: [:])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value.value(atPath: "accounts.1.balance_base") == .number(48_000))
        #expect(value["total_base"] == .number(348_000))
        #expect(value["missing_rates"] == .array([]))
    }

    @Test func convertCurrencyGivesTheAmountAndTheRate() async throws {
        let (toolkit, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "convert_currency", input: ["amount": 150, "from": "usd"])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["currency"] == "KZT")
        #expect(value["converted"] == .number(72_000))
        #expect(value["rate"] == .number(480))
        #expect(value.value(atPath: "from.currency") == "USD")
        #expect(value.value(atPath: "from.amount") == .number(150))
        #expect(value["rates_date"]?.stringValue != nil)

        // The cards show each figure in its own currency.
        let results = ["toolu_fx": value]
        let converted = try #require(AgentReplyData.metric(label: "В тенге", source: "toolu_fx", path: "converted", trendPath: nil, results: results))
        #expect(converted.value == .amount(72_000, currency: "KZT"))
        let asked = try #require(AgentReplyData.metric(label: "Доллары", source: "toolu_fx", path: "from.amount", trendPath: nil, results: results))
        #expect(asked.value == .amount(150, currency: "USD"))

        let back = await toolkit.execute(name: "convert_currency", input: ["amount": 4_800, "from": "KZT", "to": "USD"])
        #expect(back.value?["converted"] == .number(10))
        #expect(back.value?["rate"] == .number(0.002083))

        let unknown = await toolkit.execute(name: "convert_currency", input: ["from": "ZZZ"])
        #expect(unknown.error?.contains("no exchange rate") == true)
    }
}
