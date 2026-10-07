//
//  AccountAggregatesRecordedConversionTests.swift
//  TenraTests
//
//  Account-detail totals (accountAggregatesByAccountId) valued a transaction in another
//  currency than its account at TODAY's rate, while the balance moved by the conversion
//  recorded with it: a 100 $ expense saved at 450 ₸ took 45 000 ₸ off the balance and
//  showed 50 000 ₸ in "Total expense". They now count the recorded conversion
//  (TransactionConversion.recordedAmount) and fall back to today's rate only without one.
//
//  @MainActor + .sharedProcessState: the tests seed the process-global
//  CurrencyRateStore.shared (cleared in init) and read/write the rule marker in
//  UserDefaults.standard (restored after).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct AccountAggregatesRecordedConversionTests {

    init() {
        CurrencyRateStore.shared.clearAll()
        // Today's rate: 1 USD = 500 ₸, 1 EUR = 550 ₸. The transactions below were
        // recorded at 450 ₸ per dollar.
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500, "EUR": 550],
            date: Date(),
            providerName: "test"
        ))
    }

    // MARK: - Fixtures

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.aggregates.\(UUID().uuidString)")!
        )
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.accounts = [
            Account(id: "kzt", name: "Tenge", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "eur", name: "Euro", currency: "EUR", createdDate: Date(), balance: 0),
            Account(id: "usd", name: "Dollars", currency: "USD", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        return store
    }

    private static func tx(
        id: String = UUID().uuidString, date: String = "2026-05-01",
        amount: Double, currency: String, type: TransactionType = .expense,
        accountId: String = "kzt", targetAccountId: String? = nil,
        convertedAmount: Double? = nil, targetCurrency: String? = nil, targetAmount: Double? = nil
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: "t", amount: amount, currency: currency,
            convertedAmount: convertedAmount, type: type, category: "Food",
            accountId: accountId, targetAccountId: targetAccountId,
            targetCurrency: targetCurrency, targetAmount: targetAmount
        )
    }

    private func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.01
    }

    // MARK: - Recorded conversion

    @Test("a cross-currency expense counts what the balance moved by, not today's rate")
    func recordedConversionNotTodaysRate() {
        let store = Self.makeStore()
        store.accountAggregatesAdd(Self.tx(amount: 100, currency: "USD", convertedAmount: 45_000))
        #expect(close(store.accountAggregatesByAccountId["kzt"]?.totalExpense, 45_000), "was 50 000 at today's rate")

        store.accountAggregatesAdd(Self.tx(amount: 100, currency: "USD", convertedAmount: 45_000,
                                           targetCurrency: "KZT", targetAmount: 45_000))
        #expect(close(store.accountAggregatesByAccountId["kzt"]?.totalExpense, 90_000))
    }

    @Test("the equivalent labelled with the account's currency wins over an older base-currency convertedAmount")
    func labelledEquivalentWins() {
        let store = Self.makeStore()
        // The add screen used to store the base (tenge) value as convertedAmount.
        store.accountAggregatesAdd(Self.tx(amount: 100, currency: "USD", accountId: "eur",
                                           convertedAmount: 45_000, targetCurrency: "EUR", targetAmount: 82))
        #expect(close(store.accountAggregatesByAccountId["eur"]?.totalExpense, 82))
    }

    @Test("without a recorded conversion in the account's currency, today's rate as before")
    func fallsBackToTodaysRate() {
        let store = Self.makeStore()
        // No conversion stored at all.
        store.accountAggregatesAdd(Self.tx(amount: 100, currency: "USD"))
        #expect(close(store.accountAggregatesByAccountId["kzt"]?.totalExpense, 50_000))
        // A label naming another currency than the account's: the account's currency
        // was changed after the save.
        store.accountAggregatesAdd(Self.tx(amount: 100, currency: "USD", accountId: "eur",
                                           convertedAmount: 45_000, targetCurrency: "KZT", targetAmount: 45_000))
        #expect(close(store.accountAggregatesByAccountId["eur"]?.totalExpense, 100.0 * 500 / 550))
    }

    @Test("a transfer counts its source leg as recorded and its target leg as received")
    func transferLegs() {
        let store = Self.makeStore()
        store.accountAggregatesAdd(Self.tx(amount: 100, currency: "USD", type: .internalTransfer,
                                           accountId: "kzt", targetAccountId: "eur",
                                           convertedAmount: 45_000, targetCurrency: "EUR", targetAmount: 91))
        #expect(close(store.accountAggregatesByAccountId["kzt"]?.totalExpense, 45_000))
        #expect(close(store.accountAggregatesByAccountId["eur"]?.totalIncome, 91))
    }

    // MARK: - Cache keys (CLAUDE.md red flag 12)

    @Test("editing only convertedAmount moves the total")
    func convertedAmountIsBucketAffecting() {
        let store = Self.makeStore()
        let old = Self.tx(id: "t1", amount: 100, currency: "USD", convertedAmount: 45_000)
        let new = Self.tx(id: "t1", amount: 100, currency: "USD", convertedAmount: 46_000)
        store.accountAggregatesAdd(old)
        store.accountAggregatesUpdate(old: old, new: new)
        #expect(close(store.accountAggregatesByAccountId["kzt"]?.totalExpense, 46_000))
    }

    @Test("moving a planned transaction to a past date counts it")
    func dateIsBucketAffecting() {
        let store = Self.makeStore()
        let future = DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: 20, to: Date())!
        )
        let planned = Self.tx(id: "t1", date: future, amount: 1_000, currency: "KZT")
        let paid = Self.tx(id: "t1", date: "2026-05-01", amount: 1_000, currency: "KZT")
        store.accountAggregatesAdd(planned)
        #expect((store.accountAggregatesByAccountId["kzt"]?.totalExpense ?? 0) == 0)
        store.accountAggregatesUpdate(old: planned, new: paid)
        #expect(close(store.accountAggregatesByAccountId["kzt"]?.totalExpense, 1_000))
        #expect(store.accountAggregatesByAccountId["kzt"]?.totalTransactions == 1)
    }

    // MARK: - Cold rebuild

    @Test("the incremental path, the rebuild and the cold-start snapshot agree")
    func allPathsAgree() throws {
        let store = Self.makeStore()
        let transactions = [
            Self.tx(amount: 100, currency: "USD", convertedAmount: 45_000),
            Self.tx(amount: 100, currency: "USD", accountId: "eur",
                    convertedAmount: 45_000, targetCurrency: "EUR", targetAmount: 82),
            Self.tx(amount: 100, currency: "USD"),
            Self.tx(amount: 100, currency: "USD", type: .internalTransfer, accountId: "kzt",
                    targetAccountId: "usd", convertedAmount: 45_000, targetCurrency: "USD", targetAmount: 100),
            Self.tx(amount: 2_000, currency: "KZT", type: .income)
        ]
        store.transactions = transactions
        for transaction in transactions { store.accountAggregatesAdd(transaction) }
        let incremental = store.accountAggregatesByAccountId

        store.rebuildAccountAggregates()
        let rebuilt = store.accountAggregatesByAccountId

        let snapshot = TransactionStore.buildLoadSnapshot(
            transactions: transactions,
            categories: [],
            subcategories: [],
            categorySubcategoryLinks: [],
            transactionSubcategoryLinks: [],
            baseCurrency: "KZT",
            accountsCurrencyById: ["kzt": "KZT", "eur": "EUR", "usd": "USD"],
            needsColdStartCategoryAggregates: false,
            needsColdStartAccountAggregates: true
        )
        let cold = try #require(snapshot.coldStartAccountAggregates)

        for id in ["kzt", "eur", "usd"] {
            for map in [rebuilt, cold] {
                #expect(close(map[id]?.totalExpense, incremental[id]?.totalExpense ?? .nan), "expense \(id)")
                #expect(close(map[id]?.totalIncome, incremental[id]?.totalIncome ?? .nan), "income \(id)")
                #expect(map[id]?.totalTransactions == incremental[id]?.totalTransactions, "count \(id)")
            }
        }
        #expect(close(incremental["kzt"]?.totalExpense, 45_000 + 50_000 + 45_000))
    }

    // MARK: - Totals saved under the previous rule

    @Test("only a flush after the full load marks the saved totals as following the current rule")
    func ruleMarker() async {
        let key = TransactionStore.accountAggregatesRuleVersionKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(!TransactionStore.persistedAccountAggregatesFollowCurrentRule,
                "totals saved before the rule existed are rebuilt by the next load")

        let store = Self.makeStore()
        store.hasCompletedInitialLoad = false
        await store.flushAccountAggregatePersist()
        #expect(!TransactionStore.persistedAccountAggregatesFollowCurrentRule,
                "before the full load the table is emptied, not rewritten")

        store.hasCompletedInitialLoad = true
        await store.flushAccountAggregatePersist()
        #expect(TransactionStore.persistedAccountAggregatesFollowCurrentRule)
    }
}
