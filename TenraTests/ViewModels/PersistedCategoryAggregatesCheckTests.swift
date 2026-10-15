//
//  PersistedCategoryAggregatesCheckTests.swift
//  TenraTests
//
//  The full load warm-starts the category totals from the table the last session saved
//  only while that table still describes the transactions
//  (`TransactionStore.persistedCategoryAggregatesMatch`); otherwise it rebuilds them.
//  Until 1.5 an App Intent run before the full load (the Wallet automation) saved the one
//  payment it added as the whole table, a warm start kept adding deltas to it, and every
//  budget on the Categories screen read 0.
//
//  `.serialized` + `.sharedProcessState`: loadData reconciles the process-wide order managers.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct PersistedCategoryAggregatesCheckTests {

    private static func day(_ offset: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private static func expense(_ id: String, _ amount: Double, _ category: String, on offset: Int) -> Transaction {
        Transaction(id: id, date: day(offset), description: id, amount: amount, currency: "KZT",
                    type: .expense, category: category, accountId: "a")
    }

    private static var transactions: [Transaction] {
        [
            expense("t1", 1000, "Food", on: -3),
            expense("t2", 500, "Food", on: -1),
            expense("t3", 700, "Travel", on: -2),
            expense("t4", 900, "Food", on: 10)  // future-dated: not in the totals yet
        ]
    }

    private static func parsedDates(_ transactions: [Transaction]) -> [String: Date] {
        var dates: [String: Date] = [:]
        for tx in transactions { dates[tx.date] = FastDateParser.date(from: tx.date) }
        return dates
    }

    private static func rebuilt(_ transactions: [Transaction]) -> [CategoryAggregate] {
        Array(TransactionStore.computeCategoryAggregates(
            transactions: transactions,
            parsedDates: parsedDates(transactions),
            baseCurrency: "KZT"
        ).aggregates.values)
    }

    /// Whether `table` passes the check against `transactions`.
    private static func matches(_ table: [CategoryAggregate]) -> Bool {
        TransactionStore.persistedCategoryAggregatesMatch(
            table, transactions: transactions, parsedDates: parsedDates(transactions)
        )
    }

    // MARK: - The check

    @Test func aTableRebuiltFromTheTransactionsMatches() {
        #expect(Self.matches(Self.rebuilt(Self.transactions)))
    }

    @Test func aTableSavedFromOnePaymentDoesNotMatch() {
        // What an App Intent run before the full load saved: only the payment it added.
        #expect(!Self.matches(Self.rebuilt([Self.expense("t3", 700, "Travel", on: -2)])))
    }

    @Test func aTableMissingACategoryDoesNotMatch() {
        let withoutFood = Self.rebuilt(Self.transactions).filter { $0.categoryName != "Food" }
        #expect(!Self.matches(withoutFood))
    }

    @Test func aTableSavedBeforeATransactionCameDueDoesNotMatch() {
        // Saved while t2 was still in the future: now it is due, so the totals lack it.
        let savedEarlier = Self.rebuilt(Self.transactions.filter { $0.id != "t2" })
        #expect(!Self.matches(savedEarlier))
    }

    @Test func emptyBucketsLeftByRemovalsAreIgnored() {
        // A removal that leaves FX residue keeps a bucket with no transactions.
        let residue = CategoryAggregate(categoryName: "Old", year: 0, month: 0,
                                        totalAmount: 0.003, transactionCount: 0, currency: "KZT")
        #expect(Self.matches(Self.rebuilt(Self.transactions) + [residue]))
    }

    // MARK: - The load

    private static func makeStore(persisted: [CategoryAggregate]) -> (TransactionStore, RecordingDataRepository, BalanceCoordinator) {
        let repo = RecordingDataRepository()
        let card = Account(id: "a", name: "Card", currency: "KZT", initialBalance: 0, balance: 0)
        let categories = [
            CustomCategory(id: "food", name: "Food", colorHex: "#22c55e", type: .expense),
            CustomCategory(id: "travel", name: "Travel", colorHex: "#3b82f6", type: .expense)
        ]
        repo.saveAccounts([card])
        repo.saveCategories(categories)
        repo.saveTransactions(transactions)
        repo.persistedCategoryAggregates = persisted

        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance,
                                     recurringStore: RecurringStore(repository: repo))
        // What `loadAccountsOnly` does at launch: accounts and categories in memory.
        store.accounts = [card]
        store.rebuildAccountById()
        store.categories = categories
        store.rebuildCategoryLookups()
        store.hasLoadedAccountsAndCategories = true
        return (store, repo, balance)
    }

    private static func expenseTotals(_ aggregates: [String: CategoryAggregate]) -> [String: Double] {
        aggregates.mapValues(\.expenseAmount)
    }

    @Test func theLoadRebuildsAWrongTable() async throws {
        let partial = Self.rebuilt([Self.expense("t3", 700, "Travel", on: -2)])
        let (store, _, _) = Self.makeStore(persisted: partial)

        try await store.loadData()

        let expected = Dictionary(uniqueKeysWithValues: Self.rebuilt(Self.transactions).map { ($0.id, $0.expenseAmount) })
        #expect(Self.expenseTotals(store.categoryAggregatesByKey) == expected)
        #expect(store.categoryAggregatesByKey[CategoryAggregate.makeId(category: "Food", year: 0, month: 0)]?.expenseAmount == 1500)
    }

    @Test func theLoadKeepsAMatchingTable() async throws {
        // The counts match, so the saved table is used as is: its marked total survives.
        let marked = Self.rebuilt(Self.transactions).map { aggregate -> CategoryAggregate in
            guard aggregate.categoryName == "Food", aggregate.year == 0 else { return aggregate }
            return CategoryAggregate(categoryName: "Food", year: 0, month: 0, totalAmount: 99_999,
                                     expenseAmount: 99_999, transactionCount: aggregate.transactionCount,
                                     currency: "KZT")
        }
        let (store, _, _) = Self.makeStore(persisted: marked)

        try await store.loadData()

        #expect(store.categoryAggregatesByKey[CategoryAggregate.makeId(category: "Food", year: 0, month: 0)]?.expenseAmount == 99_999)
    }
}
