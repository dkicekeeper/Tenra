//
//  AccountRepositoryTests.swift
//  TenraTests
//
//  Tests for AccountRepositoryProtocol contract and AccountEntity conversions.
//  Phase B upgrade: from smoke test → real protocol-contract + entity-level tests.
//  TEST-09
//

import Testing
import CoreData
import Foundation
@testable import Tenra

// MARK: - Protocol Contract Tests

/// Verifies that AccountRepositoryProtocol's method signatures are stable.
/// Acts as a compile-time regression guard — if the protocol changes, these tests break at build time.
@Suite("AccountRepositoryProtocol Contract")
struct AccountRepositoryProtocolTests {

    @Test("Protocol has loadAccounts → [Account]")
    func testLoadAccountsSignature() {
        let mock: any AccountRepositoryProtocol = MockAccountRepository()
        let accounts = mock.loadAccounts()
        #expect(accounts.isEmpty, "Fresh mock returns empty")
    }

    @Test("Protocol has saveAccounts(_ accounts: [Account])")
    func testSaveAccountsSignature() {
        let mock: any AccountRepositoryProtocol = MockAccountRepository()
        mock.saveAccounts([])
        #expect(true)
    }

    @Test("Protocol has updateAccountBalance(accountId:balance:)")
    func testUpdateAccountBalanceSignature() {
        let mock: any AccountRepositoryProtocol = MockAccountRepository()
        mock.updateAccountBalance(accountId: "test-id", balance: 1_000)
        #expect(true)
    }

    @Test("Protocol has loadAllAccountBalances → [String: Double]")
    func testLoadAllAccountBalancesSignature() {
        let mock: any AccountRepositoryProtocol = MockAccountRepository()
        let balances = mock.loadAllAccountBalances()
        #expect(balances.isEmpty)
    }
}

// MARK: - Mock Implementation

private final class MockAccountRepository: AccountRepositoryProtocol {
    private(set) var savedAccounts: [Account] = []
    private(set) var balanceUpdates: [String: Double] = [:]

    func loadAccounts() -> [Account] { [] }

    /// Mirrors the real `AccountRepository.saveAccountsInternal` UPDATE contract:
    /// for an account that already exists (by id), `balance` and `initialBalance`
    /// are managed by BalanceCoordinator and are NOT overwritten here. New
    /// accounts are inserted as-is. Modeling this prevents the mock from giving
    /// false confidence about the balance-clobber class (M-12).
    private func mergePreservingBalances(_ accounts: [Account]) {
        var existingById: [String: Account] = [:]
        for account in savedAccounts { existingById[account.id] = account }

        var result: [Account] = []
        for incoming in accounts {
            if let existing = existingById[incoming.id] {
                var merged = incoming
                merged.balance = existing.balance
                merged.initialBalance = existing.initialBalance
                result.append(merged)
            } else {
                result.append(incoming)
            }
        }
        savedAccounts = result
    }

    func saveAccounts(_ accounts: [Account]) {
        mergePreservingBalances(accounts)
    }

    func saveAccountsSync(_ accounts: [Account]) throws {
        mergePreservingBalances(accounts)
    }

    func updateAccountBalance(accountId: String, balance: Double) {
        balanceUpdates[accountId] = balance
    }

    func updateAccountBalances(_ balances: [String: Double]) {
        for (id, balance) in balances { balanceUpdates[id] = balance }
    }

    func updateAccountBalancesSync(_ balances: [String: Double]) async {
        for (id, balance) in balances { balanceUpdates[id] = balance }
    }

    func loadAllAccountBalances() -> [String: Double] { [:] }

    // Schema v9: account aggregates persistence (no-op for mock).
    func loadAccountAggregates() -> [String: AccountAggregates] { [:] }
    func saveAccountAggregates(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) {}
}

// MARK: - Mock-Based Behaviour Tests

@Suite("AccountRepository Mock Behaviour")
struct AccountRepositoryMockTests {

    @Test("saveAccounts stores accounts")
    func testSaveAccountsStored() {
        let repo = MockAccountRepository()
        let accounts = [
            Account(id: "a1", name: "Wallet", currency: "KZT",
                    iconSource: nil, depositInfo: nil, loanInfo: nil,
                    createdDate: nil, shouldCalculateFromTransactions: false,
                    initialBalance: 10_000, balance: 10_000),
            Account(id: "a2", name: "Card", currency: "USD",
                    iconSource: nil, depositInfo: nil, loanInfo: nil,
                    createdDate: nil, shouldCalculateFromTransactions: false,
                    initialBalance: 500, balance: 500),
        ]
        repo.saveAccounts(accounts)
        #expect(repo.savedAccounts.count == 2)
        #expect(repo.savedAccounts.map(\.id) == ["a1", "a2"])
    }

    @Test("updateAccountBalance stores new balance by ID")
    func testUpdateAccountBalance() {
        let repo = MockAccountRepository()
        repo.updateAccountBalance(accountId: "a1", balance: 99_999)
        #expect(repo.balanceUpdates["a1"] == 99_999)
    }

    @Test("updateAccountBalances batch stores all IDs")
    func testUpdateAccountBalancesBatch() {
        let repo = MockAccountRepository()
        repo.updateAccountBalances(["a1": 1_000, "a2": 2_000, "a3": 3_000])
        #expect(repo.balanceUpdates.count == 3)
        #expect(repo.balanceUpdates["a2"] == 2_000)
    }

    /// M-12: the real `AccountRepository.saveAccountsInternal` UPDATE path
    /// deliberately does NOT write `balance`/`initialBalance` for an account
    /// that already exists — those are owned by BalanceCoordinator. The mock
    /// must mirror that so tests can't give false confidence on the
    /// balance-clobber class.
    @Test("saveAccounts does not change an existing account's balance")
    func testSaveAccountsPreservesExistingBalance() {
        let repo = MockAccountRepository()
        let original = Account(
            id: "a1", name: "Wallet", currency: "KZT",
            iconSource: nil, depositInfo: nil, loanInfo: nil,
            createdDate: nil, shouldCalculateFromTransactions: false,
            initialBalance: 10_000, balance: 10_000)
        repo.saveAccounts([original])

        // A subsequent save of the SAME account with a different (e.g. stale,
        // in-memory) balance must NOT overwrite the persisted balance.
        let stale = Account(
            id: "a1", name: "Wallet Renamed", currency: "KZT",
            iconSource: nil, depositInfo: nil, loanInfo: nil,
            createdDate: nil, shouldCalculateFromTransactions: false,
            initialBalance: 999_999, balance: 999_999)
        repo.saveAccounts([stale])

        let saved = repo.savedAccounts.first { $0.id == "a1" }
        #expect(saved?.balance == 10_000, "balance must be preserved on update")
        #expect(saved?.initialBalance == 10_000, "initialBalance must be preserved on update")
        // Non-balance fields DO update.
        #expect(saved?.name == "Wallet Renamed")
    }

    /// New accounts (id not seen before) ARE inserted with their incoming balance.
    @Test("saveAccounts inserts a new account with its incoming balance")
    func testSaveAccountsInsertsNewBalance() {
        let repo = MockAccountRepository()
        repo.saveAccounts([
            Account(id: "a1", name: "Wallet", currency: "KZT",
                    iconSource: nil, depositInfo: nil, loanInfo: nil,
                    createdDate: nil, shouldCalculateFromTransactions: false,
                    initialBalance: 10_000, balance: 10_000)
        ])
        // Second save introduces a NEW account a2 alongside existing a1.
        repo.saveAccounts([
            Account(id: "a1", name: "Wallet", currency: "KZT",
                    iconSource: nil, depositInfo: nil, loanInfo: nil,
                    createdDate: nil, shouldCalculateFromTransactions: false,
                    initialBalance: 0, balance: 0),
            Account(id: "a2", name: "Card", currency: "USD",
                    iconSource: nil, depositInfo: nil, loanInfo: nil,
                    createdDate: nil, shouldCalculateFromTransactions: false,
                    initialBalance: 500, balance: 500)
        ])
        let a2 = repo.savedAccounts.first { $0.id == "a2" }
        #expect(a2?.balance == 500, "new account keeps its incoming balance")
    }
}

// MARK: - AccountEntity Field Tests (in-memory CoreData)

@Suite("AccountEntity Integrity Tests", .serialized)
struct AccountEntityIntegrityTests {

    private func makeContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Tenra")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        desc.url = URL(string: "memory://\(UUID().uuidString)")
        desc.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [desc]
        var err: Error?
        container.loadPersistentStores { _, error in err = error }
        if let e = err { throw e }
        return container
    }

    @Test("shouldCalculateFromTransactions flag survives round-trip")
    func testShouldCalculateFromTransactionsFlag() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let account = Account(
            id: "acc-calc",
            name: "CalcAccount",
            currency: "KZT",
            iconSource: nil,
            depositInfo: nil,
            loanInfo: nil,
            createdDate: nil,
            shouldCalculateFromTransactions: true,
            initialBalance: 0,
            balance: 55_000
        )

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let result = try #require(loaded)
        #expect(result.shouldCalculateFromTransactions == true)
        // When shouldCalculateFromTransactions=true, initialBalance is resolved as 0
        #expect((result.initialBalance ?? 0) == 0.0)
    }

    @Test("Account currency code preserved")
    func testCurrencyCodePreserved() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let account = Account(
            id: "acc-kzt",
            name: "KZT Wallet",
            currency: "KZT",
            iconSource: nil,
            depositInfo: nil,
            loanInfo: nil,
            createdDate: nil,
            shouldCalculateFromTransactions: false,
            initialBalance: 250_000,
            balance: 250_000
        )

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        #expect((try #require(loaded)).currency == "KZT")
    }
}
