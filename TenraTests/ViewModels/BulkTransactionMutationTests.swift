//
//  BulkTransactionMutationTests.swift
//  TenraTests
//
//  Pins `TransactionEvent.bulkUpdated` / `.bulkDeleted` (TransactionStore+BulkMutations):
//  an account's or a category's transactions deleted together, "apply to similar", and a
//  series' payments linked or unlinked together leave EXACTLY the state the per-row path
//  (one `apply(.deleted)` / `apply(.updated)` per row) left: rows, every index, category
//  and account aggregates, subcategory counters and balances. And they write CoreData once.
//
//  Amounts are whole numbers so the balance recalculation and the per-row increments are
//  exact in binary floating point.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct BulkTransactionMutationTests {

    // MARK: - Harness

    private struct Harness {
        let store: TransactionStore
        let balance: BalanceCoordinator
        let repository: RecordingDataRepository
    }

    private static let main = "main"
    private static let savings = "savings"
    private static let loan = "loan"

    private static func makeHarness(withLoan: Bool = false) async -> Harness {
        let repository = RecordingDataRepository()
        let balance = BalanceCoordinator(repository: repository)
        let store = TransactionStore(
            repository: repository,
            balanceCoordinator: balance,
            recurringStore: RecurringStore(repository: repository)
        )
        store.categories = [
            CustomCategory(name: "Food", iconSource: .sfSymbol("cart"), colorHex: "#22c55e", type: .expense),
            CustomCategory(name: "Groceries", iconSource: .sfSymbol("basket"), colorHex: "#16a34a", type: .expense),
            CustomCategory(name: "Salary", iconSource: .sfSymbol("banknote"), colorHex: "#3b82f6", type: .income)
        ]
        store.rebuildCategoryLookups()
        var accounts = [
            Account(id: main, name: "Main", currency: "KZT", initialBalance: 100_000),
            Account(id: savings, name: "Savings", currency: "KZT", initialBalance: 50_000)
        ]
        if withLoan {
            accounts.append(Account(
                id: loan, name: "Car loan", currency: "KZT",
                loanInfo: LoanInfo(
                    bankName: "Bank", loanType: .installment, originalPrincipal: 120_000,
                    remainingPrincipal: 110_000, termMonths: 12, startDate: "2026-01-15",
                    monthlyPayment: 10_000, paymentDay: 15, paymentsMade: 1,
                    lastPaymentDate: "2026-02-15"
                ),
                initialBalance: 120_000
            ))
        }
        store.accounts = accounts
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)
        store.recurringStore.handleSeriesCreated(RecurringSeries(
            id: "S1", amount: 300, currency: "KZT", category: "Food", description: "Gym",
            accountId: main, frequency: .monthly, startDate: "2026-08-10", kind: .subscription,
            status: .active
        ))
        return Harness(store: store, balance: balance, repository: repository)
    }

    private static func futureDate(days: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: days, to: Date())!)
    }

    /// The same rows, added one by one, in both stores.
    private static func seedRows(withLoanPayment: Bool = false) -> [Transaction] {
        var rows = [
            Transaction(id: "e1", date: "2026-09-01", description: "Magnum", amount: 1500, currency: "KZT",
                        type: .expense, category: "", accountId: main, createdAt: 1),
            Transaction(id: "e2", date: "2026-09-02", description: "Magnum", amount: 2500, currency: "KZT",
                        type: .expense, category: "Food", accountId: main, createdAt: 2),
            Transaction(id: "e3", date: "2026-09-03", description: "Small", amount: 700, currency: "KZT",
                        type: .expense, category: "", accountId: savings, createdAt: 3),
            Transaction(id: "i1", date: "2026-09-05", description: "Pay", amount: 50_000, currency: "KZT",
                        type: .income, category: "Salary", accountId: main, createdAt: 4),
            Transaction(id: "x1", date: "2026-09-06", description: "To savings", amount: 10_000, currency: "KZT",
                        type: .internalTransfer, category: TransactionType.transferCategoryName,
                        accountId: main, targetAccountId: savings, targetCurrency: "KZT", targetAmount: 10_000,
                        createdAt: 5),
            Transaction(id: "f1", date: futureDate(days: 10), description: "Later", amount: 999, currency: "KZT",
                        type: .expense, category: "", accountId: main, createdAt: 6),
            Transaction(id: "s1", date: "2026-09-10", description: "Gym", amount: 300, currency: "KZT",
                        type: .expense, category: "Food", accountId: main, recurringSeriesId: "S1", createdAt: 7),
            Transaction(id: "s2", date: futureDate(days: 20), description: "Gym", amount: 300, currency: "KZT",
                        type: .expense, category: "Food", accountId: main, recurringSeriesId: "S1", createdAt: 8),
            Transaction(id: "e4", date: "2026-09-12", description: "magnum-02", amount: 800, currency: "KZT",
                        type: .expense, category: "", accountId: main, createdAt: 9)
        ]
        if withLoanPayment {
            rows.append(Transaction(
                id: "p1", date: "2026-03-15", description: "Loan", amount: 10_000, currency: "KZT",
                type: .loanPayment, category: TransactionType.loanPaymentCategoryName,
                accountId: main, targetAccountId: loan, createdAt: 10
            ))
        }
        return rows
    }

    private static func seed(_ harness: Harness, withLoanPayment: Bool = false) async throws {
        for row in seedRows(withLoanPayment: withLoanPayment) {
            _ = try await harness.store.add(row)
        }
        harness.store.subcategories = [Subcategory(id: "sub1", name: "Weekly")]
        harness.store.rebuildSubcategoryById()
        harness.store.updateTransactionSubcategoryLinks([
            TransactionSubcategoryLink(transactionId: "e1", subcategoryId: "sub1"),
            TransactionSubcategoryLink(transactionId: "e2", subcategoryId: "sub1")
        ])
    }

    /// Everything a mutation maintains, minus timestamps (`CategoryAggregate.lastUpdated`).
    private struct State: Equatable {
        struct Bucket: Equatable {
            let total: Double
            let expense: Double
            let count: Int32
            let currency: String
            let lastTransactionDate: Date?
        }
        let transactions: [Transaction]
        let transactionById: [String: Transaction]
        let transactionIdSet: Set<String>
        let transactionsCount: Int
        let byAccount: [String: [String]]
        let byCategoryName: [String: [String]]
        let bySeries: [String: [String]]
        let categoryAggregates: [String: Bucket]
        let accountAggregates: [String: AccountAggregates]
        let subcategoryUsage: [String: Int]
        let balances: [String: Double]
        let accounts: [Account]
    }

    private static func state(_ harness: Harness) -> State {
        let store = harness.store
        return State(
            transactions: store.transactions,
            transactionById: store.transactionById,
            transactionIdSet: store.transactionIdSet,
            transactionsCount: store.transactionsCount,
            byAccount: store.transactionIdsByAccount,
            byCategoryName: store.transactionIdsByCategoryName,
            bySeries: store.transactionIdsBySeriesId,
            categoryAggregates: store.categoryAggregatesByKey.mapValues {
                State.Bucket(total: $0.totalAmount, expense: $0.expenseAmount, count: $0.transactionCount,
                             currency: $0.currency, lastTransactionDate: $0.lastTransactionDate)
            },
            accountAggregates: store.accountAggregatesByAccountId,
            subcategoryUsage: store.subcategoryUsageCountById,
            balances: harness.balance.balances,
            accounts: store.accounts
        )
    }

    // MARK: - Deletes

    @Test func deletingAnAccountsTransactionsMatchesPerRowDeletes() async throws {
        let perRow = await Self.makeHarness()
        let bulk = await Self.makeHarness()
        try await Self.seed(perRow)
        try await Self.seed(bulk)

        for tx in perRow.store.transactions where tx.accountId == Self.main || tx.targetAccountId == Self.main {
            try await perRow.store.apply(.deleted(tx))
        }
        await bulk.store.deleteTransactions(forAccountId: Self.main)

        #expect(Self.state(bulk) == Self.state(perRow))
        #expect(bulk.store.transactions.map(\.id) == ["e3"])
        // One background save for all rows, none per row.
        #expect(bulk.repository.bulkDeletes.count == 1)
        #expect(Set(bulk.repository.bulkDeletes.first ?? []) == ["e1", "e2", "i1", "x1", "f1", "s1", "s2", "e4"])
        #expect(bulk.repository.rowDeletes.isEmpty)
        #expect(perRow.repository.rowDeletes.count == 8)
    }

    @Test func deletingACategorysTransactionsMatchesPerRowDeletes() async throws {
        let perRow = await Self.makeHarness()
        let bulk = await Self.makeHarness()
        try await Self.seed(perRow)
        try await Self.seed(bulk)

        for tx in perRow.store.transactions where tx.category == "Food" && tx.type == .expense {
            try await perRow.store.apply(.deleted(tx))
        }
        await bulk.store.deleteTransactions(forCategoryName: "Food", type: .expense)

        #expect(Self.state(bulk) == Self.state(perRow))
        #expect(bulk.store.transactionIdsByCategoryName["Food"] == nil)
        #expect(bulk.repository.bulkDeletes.count == 1)
    }

    @Test func aPaymentToALiveLoanIsStillDeletedOnItsOwn() async throws {
        let perRow = await Self.makeHarness(withLoan: true)
        let bulk = await Self.makeHarness(withLoan: true)
        try await Self.seed(perRow, withLoanPayment: true)
        try await Self.seed(bulk, withLoanPayment: true)

        for tx in perRow.store.transactions where tx.accountId == Self.main || tx.targetAccountId == Self.main {
            try await perRow.store.apply(.deleted(tx))
        }
        await bulk.store.deleteTransactions(forAccountId: Self.main)

        // `.deleted` takes a payment off its loan; the payment keeps that path.
        #expect(bulk.repository.rowDeletes == ["p1"])
        #expect(bulk.repository.bulkDeletes.count == 1)
        #expect(bulk.repository.bulkDeletes.first?.contains("p1") == false)
        #expect(Self.state(bulk) == Self.state(perRow))
    }

    @Test func deletingOnlyFutureRowsLeavesBalancesAsTheyWere() async throws {
        let harness = await Self.makeHarness()
        try await Self.seed(harness)
        // A balance a recalculation would change: the per-row path applied a zero delta
        // for future rows and never touched it, so the bulk path must not either.
        let mainAccount = try #require(harness.store.accountById[Self.main])
        await harness.balance.updateForAccount(mainAccount, newBalance: 1)
        let before = harness.balance.balances

        try await harness.store.deleteTransactionsInBulk(
            harness.store.transactions.filter { $0.id == "f1" || $0.id == "s2" }
        )

        #expect(harness.balance.balances == before)
        #expect(harness.balance.balances[Self.main] == 1)
        #expect(harness.store.transactionById["f1"] == nil)
        #expect(harness.store.transactionById["s2"] == nil)
    }

    // MARK: - Edits

    @Test func recategorizeMatchesPerRowUpdates() async throws {
        let perRow = await Self.makeHarness()
        let bulk = await Self.makeHarness()
        try await Self.seed(perRow)
        try await Self.seed(bulk)
        let ids = ["e1", "e3", "f1", "e4", "e1", "missing"]

        for id in ["e1", "e3", "f1", "e4"] {
            let current = try #require(perRow.store.transactionById[id])
            try await perRow.store.update(current.withCategory("Groceries"))
        }
        let moved = await bulk.store.recategorize(ids: ids, from: "", to: "Groceries")

        #expect(moved == 4)
        #expect(Self.state(bulk) == Self.state(perRow))
        #expect(bulk.repository.bulkUpdates.count == 1)
        #expect(Set(bulk.repository.bulkUpdates.first ?? []) == ["e1", "e3", "f1", "e4"])
        #expect(bulk.repository.rowUpdates.isEmpty)
    }

    @Test func unlinkingASeriesMatchesPerRowUpdates() async throws {
        let perRow = await Self.makeHarness()
        let bulk = await Self.makeHarness()
        try await Self.seed(perRow)
        try await Self.seed(bulk)

        for tx in perRow.store.transactions where tx.recurringSeriesId == "S1" {
            try await perRow.store.apply(.updated(old: tx, new: Self.withSeries(tx, nil)))
        }
        let unlinked = try await bulk.store.unlinkAllTransactions(fromSeriesId: "S1")

        #expect(unlinked == 2)
        #expect(Self.state(bulk) == Self.state(perRow))
        #expect(bulk.store.transactionIdsBySeriesId["S1"] == nil)
        #expect(bulk.repository.bulkUpdates.count == 1)
    }

    @Test func linkingPaymentsToASeriesMatchesPerRowUpdates() async throws {
        let perRow = await Self.makeHarness()
        let bulk = await Self.makeHarness()
        try await Self.seed(perRow)
        try await Self.seed(bulk)
        let picked = ["e4", "e2", "e1"]

        for id in picked.sorted(by: { perRow.store.transactionById[$0]!.date < perRow.store.transactionById[$1]!.date }) {
            let tx = try #require(perRow.store.transactionById[id])
            try await perRow.store.apply(.updated(old: tx, new: Self.withSeries(tx, "S1")))
        }
        try await bulk.store.linkTransactionsToSubscription(
            seriesId: "S1",
            transactions: picked.compactMap { bulk.store.transactionById[$0] }
        )

        #expect(Self.state(bulk) == Self.state(perRow))
        #expect(bulk.store.transactionIdsBySeriesId["S1"] == ["s1", "s2", "e1", "e2", "e4"])
    }

    @Test func updateBatchLeavesOutRowsUpdateWouldReject() async throws {
        let harness = await Self.makeHarness()
        try await Self.seed(harness)
        let e1 = try #require(harness.store.transactionById["e1"])
        let s1 = try #require(harness.store.transactionById["s1"])

        let saved = await harness.store.updateBatch([
            e1.withCategory("Groceries"),
            e1.withCategory("No such category"),           // a later version of e1 wins, and fails
            Self.withSeries(s1, nil),                      // drops a live series link
            Transaction(id: "missing", date: "2026-09-01", description: "", amount: 1,
                        currency: "KZT", type: .expense, category: "Food", accountId: Self.main)
        ])

        #expect(saved.isEmpty)
        #expect(harness.store.transactionById["e1"]?.category == "")
        #expect(harness.store.transactionById["s1"]?.recurringSeriesId == "S1")
        #expect(harness.repository.bulkUpdates.isEmpty)
    }

    private static func withSeries(_ tx: Transaction, _ seriesId: String?) -> Transaction {
        Transaction(
            id: tx.id, date: tx.date, description: tx.description, amount: tx.amount,
            currency: tx.currency, convertedAmount: tx.convertedAmount, type: tx.type,
            category: tx.category, subcategory: tx.subcategory, accountId: tx.accountId,
            targetAccountId: tx.targetAccountId, accountName: tx.accountName,
            targetAccountName: tx.targetAccountName, targetCurrency: tx.targetCurrency,
            targetAmount: tx.targetAmount, recurringSeriesId: seriesId,
            recurringOccurrenceId: seriesId == nil ? nil : tx.recurringOccurrenceId,
            createdAt: tx.createdAt
        )
    }
}
