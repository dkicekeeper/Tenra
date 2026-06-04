//
//  AccountCurrencyEditRecalcTests.swift
//  TenraTests
//
//  Cache audit #8 (combined-edit gap): AccountBalance.currency is set once at
//  registerAccounts, and recalculateAccounts reads the CACHED currency to convert
//  cross-currency legs. The currency-ONLY edit branch re-registers; the combined
//  balance+currency branch originally did NOT, so editing both at once recomputed
//  the balance in the OLD currency and left the cached currency stale until restart.
//
//  This pins that a combined edit recalculates in the NEW currency.
//
//  Determinism note: the balance engine (getTransactionAmount) does NOT use live FX —
//  for a cross-currency leg it reads the tx's STORED convertedAmount. So we give the
//  100 USD income a convertedAmount of 45 000 (its KZT value). After the edit the
//  account is USD, so tx.currency == account.currency → the engine uses tx.amount (100)
//  and the balance is 1000. If the cached AccountBalance.currency stays stale (KZT),
//  the engine sees a currency mismatch and uses convertedAmount (45 000) → balance
//  45 900. The two outcomes are orders of magnitude apart, with no rate-store dependency.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct AccountCurrencyEditRecalcTests {

    // Returns the store too — AccountsViewModel holds it weakly (CLAUDE.md).
    private static func makeGraph() -> (AccountsViewModel, BalanceCoordinator, TransactionStore) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: recurring)
        let accountsVM = AccountsViewModel(repository: repo)
        accountsVM.transactionStore = store
        accountsVM.balanceCoordinator = balance
        return (accountsVM, balance, store)
    }

    @Test("combined balance+currency edit recalculates in the NEW currency")
    func combinedCurrencyAndBalanceEditUsesNewCurrency() async throws {
        let (accountsVM, balance, store) = Self.makeGraph()

        // Account starts in KZT.
        await accountsVM.addAccount(name: "Acc", initialBalance: 0, currency: "KZT")
        guard let account = accountsVM.accounts.first else {
            Issue.record("account was not created")
            return
        }

        // One realized income of 100 USD on this account, with its KZT value (45 000)
        // stored as convertedAmount — what the balance engine falls back to on a
        // currency mismatch.
        _ = try await store.add(Transaction(
            id: "", date: "2026-01-01", description: "in",
            amount: 100, currency: "USD", convertedAmount: 45_000,
            type: .income, category: "", accountId: account.id
        ))

        // Edit: switch currency KZT → USD AND set the displayed balance to 1000
        // (this is what AccountEditView does when both fields are touched).
        var edited = account
        edited.currency = "USD"
        edited.initialBalance = 1000
        edited.shouldCalculateFromTransactions = false
        accountsVM.updateAccount(edited)

        // updateAccount recalculates on a spawned Task — let it settle. With the fix the
        // edit re-registers the account so the cached currency becomes USD → tx.currency
        // matches → engine uses tx.amount (100) → balance 1000. Without it the cached
        // currency stays KZT → engine uses convertedAmount (45 000) → balance 45 900,
        // which never converges to 1000.
        var bal = balance.balances[account.id] ?? 0
        for _ in 0..<1000 where abs(bal - 1000) > 0.5 {
            await Task.yield()
            bal = balance.balances[account.id] ?? 0
        }

        #expect(abs(bal - 1000) < 0.5,
                "combined currency+balance edit must recalc in the NEW currency (USD); got \(bal)")
    }
}
