//
//  ImportBalanceCompensationTests.swift
//  TenraTests
//
//  Importing statement rows that predate an account must not change the balance
//  the user entered when creating it; rows on/after the creation day still do.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct ImportBalanceCompensationTests {

    private static func day(_ key: String) -> Date {
        DateFormatters.dateFormatter.date(from: key)!
    }

    private static func account(
        id: String = "a1",
        created: String = "2026-09-10",
        initial: Double? = 150_000,
        fromTransactions: Bool = false
    ) -> Account {
        Account(id: id, name: "Kaspi", currency: "KZT", createdDate: day(created),
                shouldCalculateFromTransactions: fromTransactions, initialBalance: initial)
    }

    private static func expense(_ amount: Double, on date: String, account: String = "a1") -> Transaction {
        Transaction(id: UUID().uuidString, date: date, description: "row", amount: amount,
                    currency: "KZT", type: .expense, category: "", accountId: account)
    }

    // MARK: - Pure rule

    @Test func preCreationExpenseIsCompensated() {
        let shift = ImportBalanceCompensation.preCreationContribution(
            of: [Self.expense(50_000, on: "2026-08-15")], to: Self.account())
        #expect(abs(shift - (-50_000)) < 0.001)
    }

    @Test func postCreationExpenseIsNotCompensated() {
        let shift = ImportBalanceCompensation.preCreationContribution(
            of: [Self.expense(10_000, on: "2026-09-15")], to: Self.account())
        #expect(shift == 0)
    }

    @Test func rowOnCreationDayIsTreatedAsNew() {
        let shift = ImportBalanceCompensation.preCreationContribution(
            of: [Self.expense(10_000, on: "2026-09-10")], to: Self.account())
        #expect(shift == 0)
    }

    @Test func futureRowContributesNothing() {
        let future = DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(86_400 * 10))
        let shift = ImportBalanceCompensation.preCreationContribution(
            of: [Self.expense(10_000, on: future)], to: Self.account(created: "2099-01-01"))
        #expect(shift == 0)
    }

    @Test func transactionDerivedAccountIsNotCompensated() {
        let shift = ImportBalanceCompensation.preCreationContribution(
            of: [Self.expense(50_000, on: "2026-08-15")], to: Self.account(fromTransactions: true))
        #expect(shift == 0)
    }

    @Test func otherAccountsRowsAreIgnored() {
        let shift = ImportBalanceCompensation.preCreationContribution(
            of: [Self.expense(50_000, on: "2026-08-15", account: "a2")], to: Self.account())
        #expect(shift == 0)
    }

    // MARK: - Integration

    @Test func importKeepsEnteredBalanceAndCountsOnlyNewRows() async throws {
        let repo = RecordingDataRepository()
        let coordinator = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: coordinator,
                                     recurringStore: RecurringStore(repository: repo))
        let account = Self.account()
        store.addAccount(account)
        await coordinator.registerAccounts([account])
        await coordinator.setInitialBalance(150_000, for: account.id)
        await coordinator.recalculateAll(accounts: store.accounts, transactions: store.transactions)
        #expect(abs((coordinator.balances["a1"] ?? 0) - 150_000) < 0.5)

        var saved: [Transaction] = []
        saved.append(try await store.add(Self.expense(50_000, on: "2026-08-15")))
        saved.append(try await store.add(Self.expense(10_000, on: "2026-09-15")))
        await ImportBalanceCompensation.apply(saved: saved, store: store, coordinator: coordinator)

        #expect(abs((coordinator.balances["a1"] ?? 0) - 140_000) < 0.5)
        await coordinator.recalculateAll(accounts: store.accounts, transactions: store.transactions)
        #expect(abs((coordinator.balances["a1"] ?? 0) - 140_000) < 0.5, "must survive a full recalc")
        #expect(repo.persistedInitialBalances.compactMap { $0["a1"] }.last.map { abs($0 - 200_000) < 0.5 } == true)
    }
}
