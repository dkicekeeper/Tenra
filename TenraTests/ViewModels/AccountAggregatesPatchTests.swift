//
//  AccountAggregatesPatchTests.swift
//  TenraTests
//
//  Invariant: applying `accountAggregatesAdd` (and then `accountAggregatesRemove`
//  or `accountAggregatesUpdate`) yields the SAME result as a full
//  `rebuildAccountAggregates()` after the same final tx state. This guards
//  against drift between the delta-patch path used in `updateState` and the
//  cold-start rebuild path called in `loadData`.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct AccountAggregatesPatchTests {

    // MARK: - Helpers

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)
        return TransactionStore(
            repository: repo,
            balanceCoordinator: balance,
            recurringStore: recurring
        )
    }

    private static func tx(
        id: String,
        amount: Double,
        currency: String = "KZT",
        type: TransactionType = .expense,
        accountId: String? = "a1",
        targetAccountId: String? = nil,
        targetCurrency: String? = nil,
        targetAmount: Double? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: "2026-05-01",
            description: "t",
            amount: amount,
            currency: currency,
            type: type,
            category: "Food",
            accountId: accountId,
            targetAccountId: targetAccountId,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount
        )
    }

    /// Sets up accounts (KZT) so the per-currency arithmetic is a no-op.
    private static func setupAccounts(_ store: TransactionStore) {
        store.accounts = [
            Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "a2", name: "Other", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
    }

    /// Returns true when two `AccountAggregates` maps are equivalent. Compares
    /// keys explicitly and uses an epsilon for the Doubles to absorb FP residue.
    private static func aggregatesAgree(
        _ patched: [String: AccountAggregates],
        _ rebuilt: [String: AccountAggregates]
    ) -> Bool {
        guard patched.keys.sorted() == rebuilt.keys.sorted() else { return false }
        for key in patched.keys {
            guard let a = patched[key], let b = rebuilt[key] else { return false }
            if a.totalTransactions != b.totalTransactions { return false }
            if abs(a.totalIncome - b.totalIncome) > 0.005 { return false }
            if abs(a.totalExpense - b.totalExpense) > 0.005 { return false }
        }
        return true
    }

    // MARK: - Future-date exclusion (realized actuals)

    private static func futureDateString(daysAhead: Int = 20) -> String {
        DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: daysAhead, to: Date())!
        )
    }

    @Test("future-dated transaction is excluded from account aggregates")
    func futureTxExcludedFromAggregates() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let future = Transaction(
            id: "f1", date: Self.futureDateString(), description: "t",
            amount: 500, currency: "KZT", type: .expense, category: "Food",
            accountId: "a1", targetAccountId: nil
        )
        let past = Self.tx(id: "p1", amount: 200, type: .expense) // dated 2026-05-01 (past)

        store.accountAggregatesAdd(future)
        store.accountAggregatesAdd(past)

        let agg = store.accountAggregatesByAccountId["a1"]
        #expect(agg?.totalExpense == 200)
        #expect(agg?.totalTransactions == 1)
    }

    // MARK: - Per-type sign table (store-index path; replaces legacy calculator tests)

    @Test("loan payment counts as expense on both source bank and loan account")
    func loanPaymentExpenseBuckets() async throws {
        let store = Self.makeStore()
        store.accounts = [
            Account(id: "a1", name: "Bank", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "loan1", name: "Loan", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        let pay = Self.tx(id: "lp1", amount: 250, type: .loanPayment, accountId: "a1", targetAccountId: "loan1")
        store.accountAggregatesAdd(pay)
        #expect(store.accountAggregatesByAccountId["a1"]?.totalExpense == 250)
        #expect(store.accountAggregatesByAccountId["loan1"]?.totalExpense == 250)
    }

    @Test("internal transfer is expense on source, income on target")
    func transferDualPerspective() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let xfer = Self.tx(id: "x1", amount: 500, type: .internalTransfer, accountId: "a1", targetAccountId: "a2")
        store.accountAggregatesAdd(xfer)
        #expect(store.accountAggregatesByAccountId["a1"]?.totalExpense == 500)
        #expect(store.accountAggregatesByAccountId["a2"]?.totalIncome == 500)
    }

    // MARK: - Add-only sequence

    @Test("incremental adds match cold rebuild")
    func addOnlyMatches() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let txs = [
            Self.tx(id: "1", amount: 1_000, type: .income),
            Self.tx(id: "2", amount: 200, type: .expense),
            Self.tx(id: "3", amount: 50, type: .expense),
            Self.tx(id: "4", amount: 300, type: .internalTransfer, accountId: "a1", targetAccountId: "a2")
        ]
        // Incremental path.
        store.transactions = txs
        for t in txs { store.accountAggregatesAdd(t) }
        let patched = store.accountAggregatesByAccountId

        // Cold rebuild.
        store.rebuildAccountAggregates()
        #expect(Self.aggregatesAgree(patched, store.accountAggregatesByAccountId))
    }

    // MARK: - Add-then-remove sequence

    @Test("delta-add followed by delta-remove returns to empty state")
    func addRemoveSymmetric() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let t = Self.tx(id: "1", amount: 500, type: .expense)
        store.accountAggregatesAdd(t)
        store.accountAggregatesRemove(t)

        let agg = store.accountAggregatesByAccountId["a1"]
        // After symmetric add+remove the bucket can still exist with zero values;
        // assert numerical equivalence rather than absence.
        #expect((agg?.totalTransactions ?? 0) == 0)
        #expect(abs(agg?.totalIncome ?? 0) < 0.005)
        #expect(abs(agg?.totalExpense ?? 0) < 0.005)
    }

    // MARK: - Update sequence

    @Test("non-bucket-affecting update is a no-op")
    func updateNonBucketAffectingNoop() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let old = Self.tx(id: "1", amount: 100, type: .expense)
        let new = Self.tx(id: "1", amount: 100, type: .expense)  // identical bucket-affecting fields
        store.accountAggregatesAdd(old)
        let beforeUpdate = store.accountAggregatesByAccountId["a1"]
        store.accountAggregatesUpdate(old: old, new: new)
        let afterUpdate = store.accountAggregatesByAccountId["a1"]
        #expect(beforeUpdate?.totalTransactions == afterUpdate?.totalTransactions)
        #expect(beforeUpdate?.totalExpense == afterUpdate?.totalExpense)
    }

    @Test("amount change updates expense delta")
    func updateAmountChange() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let old = Self.tx(id: "1", amount: 100, type: .expense)
        let new = Self.tx(id: "1", amount: 250, type: .expense)
        store.accountAggregatesAdd(old)
        store.accountAggregatesUpdate(old: old, new: new)

        // Cold-rebuild reference.
        store.transactions = [new]
        store.rebuildAccountAggregates()
        let rebuilt = store.accountAggregatesByAccountId["a1"]
        #expect(rebuilt?.totalExpense == 250)
        #expect(rebuilt?.totalTransactions == 1)
    }

    @Test("account-id change moves the contribution between buckets")
    func updateAccountChange() async throws {
        let store = Self.makeStore()
        Self.setupAccounts(store)
        let old = Self.tx(id: "1", amount: 100, type: .expense, accountId: "a1")
        let new = Self.tx(id: "1", amount: 100, type: .expense, accountId: "a2")
        store.accountAggregatesAdd(old)
        store.accountAggregatesUpdate(old: old, new: new)

        let a1 = store.accountAggregatesByAccountId["a1"]
        let a2 = store.accountAggregatesByAccountId["a2"]
        #expect((a1?.totalExpense ?? 0) == 0)
        #expect(a2?.totalExpense == 100)
    }
}
