//
//  AccountBalanceCorrectionPersistTests.swift
//  TenraTests
//
//  A manual balance correction back-calculates a new initialBalance. It must be
//  PERSISTED (BalanceCoordinator.persistInitialBalance): AccountRepository never
//  writes initialBalance through saveAccounts, so an in-memory-only correction
//  was reverted by the next full recalc (a matured future transaction, a
//  base-currency change, an FX heal).
//
//  Also pins that the back-calculation uses the same contribution rule as the
//  forward one: future-dated transactions (e.g. a subscription's next
//  occurrence) must not shift the corrected balance.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct AccountBalanceCorrectionPersistTests {

    /// Returns the store too — AccountsViewModel holds it weakly.
    private static func makeGraph() -> (AccountsViewModel, BalanceCoordinator, TransactionStore, RecordingDataRepository) {
        let repo = RecordingDataRepository()
        let balance = BalanceCoordinator(repository: repo)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: recurring)
        let accountsVM = AccountsViewModel(repository: repo)
        accountsVM.transactionStore = store
        accountsVM.balanceCoordinator = balance
        return (accountsVM, balance, store, repo)
    }

    private static func dateKey(daysFromToday offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        return DateFormatters.dateFormatter.string(from: date)
    }

    /// Waits for the Task spawned by `updateAccount` to settle the balance.
    private static func settledBalance(_ balance: BalanceCoordinator, _ id: String, toward target: Double) async -> Double {
        var value = balance.balances[id] ?? .nan
        for _ in 0..<1000 where !(abs(value - target) < 0.5) {
            await Task.yield()
            value = balance.balances[id] ?? .nan
        }
        return value
    }

    private static func expense(_ amount: Double, on date: String, account: String) -> Transaction {
        Transaction(id: "", date: date, description: "e", amount: amount, currency: "KZT",
                    type: .expense, category: "", accountId: account)
    }

    @Test("correcting the balance persists the back-calculated initial balance")
    func correctionIsPersisted() async throws {
        let (accountsVM, balance, store, repo) = Self.makeGraph()
        await accountsVM.addAccount(name: "Card", initialBalance: 0, currency: "KZT")
        let account = try #require(accountsVM.accounts.first)
        _ = try await store.add(Self.expense(200, on: Self.dateKey(daysFromToday: -1), account: account.id))

        var edited = account
        edited.initialBalance = 1_000   // what AccountEditView passes: the desired CURRENT balance
        accountsVM.updateAccount(edited)

        let shown = await Self.settledBalance(balance, account.id, toward: 1_000)
        #expect(abs(shown - 1_000) < 0.5)

        let persisted = repo.persistedInitialBalances.compactMap { $0[account.id] }
        #expect(persisted.count == 1, "exactly one persisted correction, got \(persisted)")
        #expect(abs((persisted.first ?? 0) - 1_200) < 0.5, "initial = desired + realized expense")
    }

    @Test("a full recalculation after the correction keeps the corrected balance")
    func fullRecalcKeepsCorrection() async throws {
        let (accountsVM, balance, store, _) = Self.makeGraph()
        await accountsVM.addAccount(name: "Card", initialBalance: 0, currency: "KZT")
        let account = try #require(accountsVM.accounts.first)
        _ = try await store.add(Self.expense(200, on: Self.dateKey(daysFromToday: -1), account: account.id))

        var edited = account
        edited.initialBalance = 1_000
        accountsVM.updateAccount(edited)
        _ = await Self.settledBalance(balance, account.id, toward: 1_000)

        await balance.recalculateAll(accounts: store.accounts, transactions: store.transactions)
        #expect(abs((balance.balances[account.id] ?? 0) - 1_000) < 0.5)
    }

    @Test("a future-dated expense does not shift the corrected balance")
    func futureExpenseIgnoredByBackCalculation() async throws {
        let (accountsVM, balance, store, repo) = Self.makeGraph()
        await accountsVM.addAccount(name: "Card", initialBalance: 0, currency: "KZT")
        let account = try #require(accountsVM.accounts.first)
        _ = try await store.add(Self.expense(200, on: Self.dateKey(daysFromToday: -1), account: account.id))
        _ = try await store.add(Self.expense(5_000, on: Self.dateKey(daysFromToday: 10), account: account.id))

        var edited = account
        edited.initialBalance = 1_000
        accountsVM.updateAccount(edited)

        let shown = await Self.settledBalance(balance, account.id, toward: 1_000)
        #expect(abs(shown - 1_000) < 0.5, "future expense must not count; got \(shown)")
        let persisted = repo.persistedInitialBalances.compactMap { $0[account.id] }.first ?? .nan
        #expect(abs(persisted - 1_200) < 0.5)
    }

    @Test("an edit that does not change the balance persists nothing")
    func renameOnlyPersistsNothing() async throws {
        // Keep the store alive: AccountsViewModel holds it weakly.
        let (accountsVM, _, store, repo) = Self.makeGraph()
        await accountsVM.addAccount(name: "Card", initialBalance: 500, currency: "KZT")
        defer { withExtendedLifetime(store) {} }
        let account = try #require(accountsVM.accounts.first)

        var edited = account
        edited.name = "Main card"
        accountsVM.updateAccount(edited)
        for _ in 0..<50 { await Task.yield() }

        #expect(repo.persistedInitialBalances.isEmpty)
    }

    @Test("back-calculation and forward calculation agree")
    func backAndForwardAgree() {
        let engine = BalanceCalculationEngine()
        let account = AccountBalance(accountId: "a1", currentBalance: 0, initialBalance: nil, currency: "KZT")
        let transactions = [
            Transaction(id: "i", date: Self.dateKey(daysFromToday: -5), description: "", amount: 700,
                        currency: "KZT", type: .income, category: "", accountId: "a1"),
            Self.expense(150, on: Self.dateKey(daysFromToday: -3), account: "a1"),
            Transaction(id: "out", date: Self.dateKey(daysFromToday: -2), description: "", amount: 100,
                        currency: "KZT", type: .internalTransfer, category: TransactionType.transferCategoryName,
                        accountId: "a1", targetAccountId: "a2", targetCurrency: "KZT", targetAmount: 100),
            Transaction(id: "in", date: Self.dateKey(daysFromToday: -1), description: "", amount: 40,
                        currency: "KZT", type: .internalTransfer, category: TransactionType.transferCategoryName,
                        accountId: "a2", targetAccountId: "a1", targetCurrency: "KZT", targetAmount: 40),
            Self.expense(999, on: Self.dateKey(daysFromToday: 7), account: "a1")
        ]

        let initial = engine.calculateInitialBalance(currentBalance: 12_345, account: account, transactions: transactions)
        var withInitial = account
        withInitial.initialBalance = initial
        let forward = engine.calculateBalance(account: withInitial, transactions: transactions)

        #expect(abs(forward - 12_345) < 0.001)
    }
}
