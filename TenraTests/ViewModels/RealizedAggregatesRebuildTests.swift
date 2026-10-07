//
//  RealizedAggregatesRebuildTests.swift
//  TenraTests
//
//  Pins the off-main rebuild of the realized aggregates (TransactionStore+RealizedAggregates):
//  on a day rollover and on an FX update it leaves the same category buckets, category
//  aggregates, account aggregates and balances as a store that applied every transaction
//  through the per-row deltas. Also pins the inputs stamp that keeps a rebuild from
//  overwriting a change made while it ran, and the single-flight day-rollover pass.
//
//  `.sharedProcessState` + `.serialized`: seeds the process-global CurrencyRateStore.shared.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct RealizedAggregatesRebuildTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Harness

    private struct Harness {
        let store: TransactionStore
        let balance: BalanceCoordinator
    }

    private static func makeHarness() async -> Harness {
        let repository = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.realized.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repository)
        let store = TransactionStore(
            repository: repository,
            balanceCoordinator: balance,
            recurringStore: RecurringStore(repository: repository)
        )
        store.categories = [
            CustomCategory(name: "Food", iconSource: .sfSymbol("cart"), colorHex: "#22c55e", type: .expense),
            CustomCategory(name: "Salary", iconSource: .sfSymbol("banknote"), colorHex: "#3b82f6", type: .income)
        ]
        store.rebuildCategoryLookups()
        store.accounts = [
            Account(id: "kzt", name: "Card", currency: "KZT", initialBalance: 200_000),
            Account(id: "usd", name: "Dollars", currency: "USD", initialBalance: 1_000)
        ]
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)
        store.hasCompletedInitialLoad = true
        return Harness(store: store, balance: balance)
    }

    /// 1 USD = 450 KZT.
    private static func seedRates() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT", rates: ["USD": 450], date: Date(), providerName: "test"
        ))
    }

    private static func dayKey(_ offset: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private static func rows() -> [Transaction] {
        [
            Transaction(id: "t1", date: "2026-08-01", description: "Shop", amount: 1000, currency: "KZT",
                        type: .expense, category: "Food", accountId: "kzt", createdAt: 1),
            Transaction(id: "t2", date: "2026-08-02", description: "Online", amount: 20, currency: "USD",
                        convertedAmount: 9000, type: .expense, category: "Food", accountId: "kzt",
                        targetCurrency: "KZT", targetAmount: 9000, createdAt: 2),
            Transaction(id: "t3", date: "2026-08-03", description: "Pay", amount: 100, currency: "USD",
                        type: .income, category: "Salary", accountId: "usd", createdAt: 3),
            Transaction(id: "t4", date: "2026-08-04", description: "Move", amount: 10, currency: "USD",
                        type: .internalTransfer, category: TransactionType.transferCategoryName,
                        accountId: "usd", targetAccountId: "kzt", targetCurrency: "KZT", targetAmount: 4500,
                        createdAt: 4),
            // Dated today: the transaction that comes due on the rollover.
            Transaction(id: "t5", date: dayKey(0), description: "Gym", amount: 300, currency: "KZT",
                        type: .expense, category: "Food", accountId: "kzt", createdAt: 5),
            // Still in the future: counted nowhere.
            Transaction(id: "t6", date: dayKey(30), description: "Later", amount: 50, currency: "KZT",
                        type: .expense, category: "Food", accountId: "kzt", createdAt: 6)
        ]
    }

    private static func addRows(_ harness: Harness) async throws {
        for row in rows() {
            _ = try await harness.store.add(row)
        }
    }

    /// The realized aggregates and balances, minus timestamps (`CategoryAggregate.lastUpdated`).
    private struct Realized: Equatable {
        struct Bucket: Equatable {
            let total: Double
            let expense: Double
            let count: Int32
            let currency: String
            let lastTransactionDate: Date?
        }
        let byCategoryName: [String: [String]]
        let categoryAggregates: [String: Bucket]
        let accountAggregates: [String: AccountAggregates]
        let balances: [String: Double]
    }

    private static func realized(_ harness: Harness) -> Realized {
        Realized(
            byCategoryName: harness.store.transactionIdsByCategoryName,
            categoryAggregates: harness.store.categoryAggregatesByKey.mapValues {
                Realized.Bucket(total: $0.totalAmount, expense: $0.expenseAmount, count: $0.transactionCount,
                                currency: $0.currency, lastTransactionDate: $0.lastTransactionDate)
            },
            accountAggregates: harness.store.accountAggregatesByAccountId,
            balances: harness.balance.balances
        )
    }

    /// Waits (time-bounded) until `condition` holds.
    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Day rollover

    @Test func dayRolloverRebuildMatchesThePerRowDeltas() async throws {
        Self.seedRates()
        let reference = await Self.makeHarness()
        try await Self.addRows(reference)

        // Same rows, then every realized figure wiped: whatever the incremental state held,
        // the rollover recompute must land on what the per-row deltas produce.
        let subject = await Self.makeHarness()
        try await Self.addRows(subject)
        subject.store.categoryAggregatesByKey = [:]
        subject.store.accountAggregatesByAccountId = [:]
        subject.store.transactionIdsByCategoryName = [:]
        for account in subject.store.accounts {
            await subject.balance.updateForAccount(account, newBalance: -1)
        }
        let defaults = UserDefaults(suiteName: "ledger.\(UUID().uuidString)")!
        defaults.set(Self.dayKey(-1), forKey: "lastLedgerRecalcDate")
        let versionBefore = subject.store.categoriesMutationVersion

        let dayChanged = await subject.store.recalculateLedgerIfDayChanged(now: Date(), defaults: defaults)

        #expect(dayChanged)
        #expect(subject.store.categoriesMutationVersion == versionBefore + 1)
        #expect(Self.realized(subject) == Self.realized(reference))
        #expect(subject.store.categoryAggregatesByKey[
            CategoryAggregate.makeId(category: "Food", year: 0, month: 0, day: 0)
        ]?.totalAmount == 1000 + 9000 + 300)
        #expect(subject.store.aggregatesAreFXStale == false)
    }

    @Test func concurrentRolloverChecksFoldTheDayInOnce() async throws {
        let harness = await Self.makeHarness()
        try await Self.addRows(harness)
        let defaults = UserDefaults(suiteName: "ledger.\(UUID().uuidString)")!
        defaults.set(Self.dayKey(-1), forKey: "lastLedgerRecalcDate")
        let versionBefore = harness.store.categoriesMutationVersion

        async let first = harness.store.recalculateLedgerIfDayChanged(now: Date(), defaults: defaults)
        async let second = harness.store.recalculateLedgerIfDayChanged(now: Date(), defaults: defaults)
        let results = await [first, second]

        #expect(results.sorted { !$0 && $1 } == [false, true])
        #expect(harness.store.categoriesMutationVersion == versionBefore + 1)
    }

    // MARK: - FX update

    @Test func fxUpdateRebuildsColdAggregatesToMatchWarmDeltas() async throws {
        // Built while the rate cache is cold: USD rows fall back to the raw amount.
        let subject = await Self.makeHarness()
        try await Self.addRows(subject)
        #expect(subject.store.aggregatesAreFXStale)

        Self.seedRates()
        let reference = await Self.makeHarness()
        try await Self.addRows(reference)
        #expect(reference.store.aggregatesAreFXStale == false)

        let versionBefore = subject.store.categoriesMutationVersion
        let started = subject.store.bumpCurrencyRatesVersion()
        #expect(started)
        try await Self.waitUntil { subject.store.categoriesMutationVersion != versionBefore }

        #expect(subject.store.categoriesMutationVersion == versionBefore + 1)
        #expect(subject.store.aggregatesAreFXStale == false)
        let healed = Self.realized(subject)
        let warm = Self.realized(reference)
        #expect(healed.byCategoryName == warm.byCategoryName)
        #expect(healed.categoryAggregates == warm.categoryAggregates)
        #expect(healed.accountAggregates == warm.accountAggregates)
    }

    // MARK: - Synchronous rebuilds

    @Test func synchronousRebuildsMatchThePerRowDeltas() async throws {
        Self.seedRates()
        let harness = await Self.makeHarness()
        try await Self.addRows(harness)
        let incremental = Self.realized(harness)

        harness.store.rebuildCategoryIndexes()
        harness.store.rebuildAccountAggregates()

        #expect(Self.realized(harness) == incremental)
    }

    // MARK: - Inputs stamp

    @Test func everyInputMovesTheStamp() async throws {
        let harness = await Self.makeHarness()
        let store = harness.store
        var stamp = store.realizedAggregatesStamp()
        #expect(store.realizedAggregatesStamp() == stamp)

        func expectMoved(_ what: Comment) {
            let next = store.realizedAggregatesStamp()
            #expect(next != stamp, what)
            stamp = next
        }

        _ = try await store.add(Self.rows()[0])
        expectMoved("a transaction event")
        store.rebuildAccountById()
        expectMoved("an account change")
        store.categoriesMutationVersion &+= 1
        expectMoved("a category change")
        store.bumpCurrencyRatesVersion()
        expectMoved("an FX update")
        store.baseCurrency = "USD"
        expectMoved("a base-currency change")
        store.rebuildCategoryIndexes()
        expectMoved("a wholesale aggregate write")
        store.transactions.append(Self.rows()[1])
        expectMoved("a direct assignment of transactions")
    }
}
