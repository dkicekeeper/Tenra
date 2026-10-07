//
//  TargetedRecalculationTests.swift
//  TenraTests
//
//  `recalculateAccounts(_:accounts:transactionsByAccount:)` reads each account's own
//  bucket of the store's per-account index instead of walking every transaction once
//  per account (the old targeted recalculation was K full scans, slower than the
//  one-pass `recalculateAll` it was meant to beat). Its result must equal the full
//  recalculation's for the same accounts.
//
//  Amounts are exact in binary, so the comparison can be exact even though the two
//  paths may add the same values in a different order.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TargetedRecalculationTests {

    private struct Graph {
        let store: TransactionStore
        let balance: BalanceCoordinator
    }

    private static func day(_ offset: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private static func tx(
        _ id: String, _ type: TransactionType, _ amount: Double, on offset: Int = -1,
        currency: String = "KZT", convertedAmount: Double? = nil,
        from accountId: String, to targetId: String? = nil,
        targetAmount: Double? = nil, targetCurrency: String? = nil
    ) -> Transaction {
        Transaction(
            id: id, date: day(offset), description: id, amount: amount, currency: currency,
            convertedAmount: convertedAmount, type: type,
            category: type == .internalTransfer ? TransactionType.transferCategoryName : "",
            accountId: accountId, targetAccountId: targetId,
            targetCurrency: targetCurrency, targetAmount: targetAmount
        )
    }

    /// A store holding a mix of every case the recalculation gates on.
    private static func makeGraph() async throws -> Graph {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.targeted.\(UUID().uuidString)")!)
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance,
                                     recurringStore: RecurringStore(repository: repo))
        let loanInfo = LoanInfo(
            bankName: "Bank", loanType: .annuity, originalPrincipal: 900_000,
            interestRateAnnual: 20, termMonths: 12, startDate: day(-30), paymentDay: 5
        )
        store.accounts = [
            Account(id: "card", name: "Card", currency: "KZT", initialBalance: 1_000, balance: 1_000),
            Account(id: "cash", name: "Cash", currency: "KZT", initialBalance: 500, balance: 500),
            Account(id: "usd", name: "Dollars", currency: "USD", initialBalance: 100, balance: 100),
            Account(id: "loan", name: "Loan", currency: "KZT", loanInfo: loanInfo, initialBalance: 900_000, balance: 900_000)
        ]
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)

        let rows: [Transaction] = [
            tx("income", .income, 250.5, from: "card"),
            tx("expense", .expense, 40.25, from: "card"),
            tx("cash-expense", .expense, 60.75, from: "cash"),
            tx("to-cash", .internalTransfer, 100, from: "card", to: "cash", targetAmount: 100, targetCurrency: "KZT"),
            tx("to-usd", .internalTransfer, 5_120, from: "card", to: "usd", targetAmount: 10.5, targetCurrency: "USD"),
            tx("usd-in-kzt", .expense, 1_024, currency: "KZT", convertedAmount: 2.25, from: "usd"),
            tx("self", .internalTransfer, 8, from: "cash", to: "cash", targetAmount: 8, targetCurrency: "KZT"),
            tx("future", .expense, 999, on: 5, from: "card"),
            tx("loan-pay", .loanPayment, 75_000, from: "card", to: "loan")
        ]
        for row in rows {
            _ = try await store.add(row)
        }
        return Graph(store: store, balance: balance)
    }

    private static func scramble(_ graph: Graph) async {
        for account in graph.store.accounts {
            await graph.balance.updateForAccount(account, newBalance: -12_345)
        }
    }

    @Test("Recalculating every account from the index equals the full recalculation")
    func indexRecalcMatchesFullRecalc() async throws {
        let graph = try await Self.makeGraph()
        await graph.balance.recalculateAll(accounts: graph.store.accounts, transactions: graph.store.transactions)
        let full = graph.balance.balances

        await Self.scramble(graph)
        await graph.balance.recalculateAccounts(
            Set(graph.store.accounts.map(\.id)),
            accounts: graph.store.accounts,
            transactionsByAccount: graph.store.transactionsByAccount
        )

        #expect(graph.balance.balances == full)
        // Spot checks against hand arithmetic: card = 1000 + 250.5 − 40.25 − 100 − 5120 − 75000.
        #expect(full["card"] == -79_009.75)
        // The self-transfer counts once: cash = 500 − 60.75 + 100 − 8.
        #expect(full["cash"] == 531.25)
        // Cross-currency legs use the account-currency amounts: usd = 100 + 10.5 − 2.25.
        #expect(full["usd"] == 108.25)
    }

    @Test("Only the requested accounts are recalculated")
    func onlyRequestedAccounts() async throws {
        let graph = try await Self.makeGraph()
        await graph.balance.recalculateAll(accounts: graph.store.accounts, transactions: graph.store.transactions)
        let full = graph.balance.balances

        await Self.scramble(graph)
        await graph.balance.recalculateAccounts(
            ["cash", "usd"],
            accounts: graph.store.accounts,
            transactionsByAccount: graph.store.transactionsByAccount
        )

        #expect(graph.balance.balances["cash"] == full["cash"])
        #expect(graph.balance.balances["usd"] == full["usd"])
        #expect(graph.balance.balances["card"] == -12_345)
    }

    @Test("An edit that moves a transaction to another account still matches the full recalculation")
    func editMovingAccountsMatches() async throws {
        let graph = try await Self.makeGraph()
        let expense = try #require(graph.store.transactionById["expense"])
        let moved = Self.tx("expense", .expense, 40.25, from: "cash")
        try await graph.store.update(Transaction(
            id: expense.id, date: expense.date, description: expense.description,
            amount: moved.amount, currency: moved.currency, type: moved.type,
            category: moved.category, accountId: "cash", createdAt: expense.createdAt
        ))

        await graph.balance.recalculateAll(accounts: graph.store.accounts, transactions: graph.store.transactions)
        let full = graph.balance.balances
        await Self.scramble(graph)
        await graph.balance.recalculateAccounts(
            ["card", "cash"],
            accounts: graph.store.accounts,
            transactionsByAccount: graph.store.transactionsByAccount
        )

        #expect(graph.balance.balances["card"] == full["card"])
        #expect(graph.balance.balances["cash"] == full["cash"])
    }

    @Test("The array overload agrees with the index overload")
    func arrayOverloadAgrees() async throws {
        let graph = try await Self.makeGraph()
        let ids = Set(graph.store.accounts.map(\.id))
        await graph.balance.recalculateAccounts(
            ids, accounts: graph.store.accounts, transactionsByAccount: graph.store.transactionsByAccount
        )
        let fromIndex = graph.balance.balances

        await Self.scramble(graph)
        await graph.balance.recalculateAccounts(ids, accounts: graph.store.accounts, transactions: graph.store.transactions)

        #expect(graph.balance.balances == fromIndex)
    }
}
