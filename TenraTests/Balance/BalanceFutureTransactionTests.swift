//
//  BalanceFutureTransactionTests.swift
//  TenraTests
//
//  Regression coverage for the incremental/recalc date asymmetry:
//  full recalculation (`calculateBalanceFromInitial`) excludes future-dated
//  transactions (`txDate <= today`), but the incremental add/remove/update
//  paths used to ignore the date entirely. That meant a future expense never
//  reduced the balance during recalc, yet deleting it incrementally added its
//  amount back — silently inflating the account balance.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct BalanceFutureTransactionTests {

    private static func makeCoordinator() -> BalanceCoordinator {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        return BalanceCoordinator(repository: repo)
    }

    private static func account(id: String = "a1", balance: Double) -> Account {
        Account(id: id, name: "Bank", currency: "KZT", initialBalance: balance, balance: balance)
    }

    private static func futureDateString(daysAhead: Int = 30) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysAhead, to: Date())!
        return DateFormatters.dateFormatter.string(from: date)
    }

    private static func pastDateString(daysAgo: Int = 30) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return DateFormatters.dateFormatter.string(from: date)
    }

    private static func expenseTx(
        id: String = UUID().uuidString,
        amount: Double,
        date: String,
        accountId: String = "a1"
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: "",
            amount: amount, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Food", subcategory: nil,
            accountId: accountId, targetAccountId: nil
        )
    }

    @Test("Deleting a future-dated expense does NOT change the balance")
    func deleteFutureExpense_noBalanceChange() async {
        let coordinator = Self.makeCoordinator()
        let acc = Self.account(balance: 100_000)
        await coordinator.registerAccounts([acc])

        let future = Self.expenseTx(amount: 5_000, date: Self.futureDateString())
        await coordinator.updateForTransaction(future, operation: .remove(future))

        #expect(coordinator.balances["a1"] == 100_000)
    }

    @Test("Adding a future-dated expense does NOT change the balance")
    func addFutureExpense_noBalanceChange() async {
        let coordinator = Self.makeCoordinator()
        let acc = Self.account(balance: 100_000)
        await coordinator.registerAccounts([acc])

        let future = Self.expenseTx(amount: 5_000, date: Self.futureDateString())
        await coordinator.updateForTransaction(future, operation: .add(future))

        #expect(coordinator.balances["a1"] == 100_000)
    }

    @Test("Deleting a past-dated expense still restores its amount")
    func deletePastExpense_restoresBalance() async {
        let coordinator = Self.makeCoordinator()
        let acc = Self.account(balance: 100_000)
        await coordinator.registerAccounts([acc])

        let past = Self.expenseTx(amount: 5_000, date: Self.pastDateString())
        await coordinator.updateForTransaction(past, operation: .remove(past))

        #expect(coordinator.balances["a1"] == 105_000)
    }

    @Test("Adding a past-dated expense still reduces the balance")
    func addPastExpense_reducesBalance() async {
        let coordinator = Self.makeCoordinator()
        let acc = Self.account(balance: 100_000)
        await coordinator.registerAccounts([acc])

        let past = Self.expenseTx(amount: 5_000, date: Self.pastDateString())
        await coordinator.updateForTransaction(past, operation: .add(past))

        #expect(coordinator.balances["a1"] == 95_000)
    }
}
