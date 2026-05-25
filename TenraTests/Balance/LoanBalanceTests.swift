//
//  LoanBalanceTests.swift
//  TenraTests
//
//  C-3: a loan account's balance is the OUTSTANDING PRINCIPAL (loanInfo.remainingPrincipal),
//  not "initial − sum of full payments". A loan payment reduces the source bank by the full
//  amount (principal + interest) but the debt only by the principal portion — interest is a
//  bank expense, not debt reduction. These pin that the balance derives from remainingPrincipal.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct LoanBalanceTests {

    private static func makeCoordinator() -> BalanceCoordinator {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        return BalanceCoordinator(repository: repo)
    }

    private static func pastDate(daysAgo: Int = 5) -> String {
        DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )
    }

    private static func loanAccount(remaining: Decimal) -> Account {
        let info = LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 1_000_000, remainingPrincipal: remaining,
            interestRateAnnual: 12, termMonths: 12,
            startDate: "2026-01-01", paymentDay: 1
        )
        return Account(id: "loan", name: "Loan", currency: "KZT", loanInfo: info,
                       initialBalance: 1_000_000, balance: 1_000_000)
    }

    @Test("loan account balance equals remainingPrincipal after recalc, not initial minus full payment")
    func loanBalanceIsRemainingPrincipal() async {
        let coordinator = Self.makeCoordinator()
        let bank = Account(id: "bank", name: "Bank", currency: "KZT", initialBalance: 500_000, balance: 500_000)
        // Debt already reduced to 800k principal (e.g. 200k principal paid so far).
        let loan = Self.loanAccount(remaining: 800_000)
        await coordinator.registerAccounts([bank, loan])
        await coordinator.setInitialBalance(500_000, for: "bank")

        // A 100k payment = 80k principal + 20k interest (the tx carries the full 100k).
        let pay = Transaction(
            id: "p1", date: Self.pastDate(), description: "",
            amount: 100_000, currency: "KZT", convertedAmount: nil,
            type: .loanPayment, category: "", subcategory: nil,
            accountId: "bank", targetAccountId: "loan"
        )
        await coordinator.updateForTransaction(pay, operation: .add(pay))
        await coordinator.recalculateAll(accounts: [bank, loan], transactions: [pay])

        // Loan balance = outstanding principal (800k), NOT 1_000_000 - 100_000.
        #expect(coordinator.balances["loan"] == 800_000)
        // Bank reduced by the full payment.
        #expect(coordinator.balances["bank"] == 400_000)
    }

    @Test("incremental loan payment does not change the loan account balance")
    func incrementalLoanPaymentLeavesLoanBalance() async {
        let coordinator = Self.makeCoordinator()
        let bank = Account(id: "bank", name: "Bank", currency: "KZT", initialBalance: 500_000, balance: 500_000)
        let loan = Self.loanAccount(remaining: 800_000)
        await coordinator.registerAccounts([bank, loan])
        await coordinator.setInitialBalance(500_000, for: "bank")
        let loanBalanceBefore = coordinator.balances["loan"]

        let pay = Transaction(
            id: "p1", date: Self.pastDate(), description: "",
            amount: 100_000, currency: "KZT", convertedAmount: nil,
            type: .loanPayment, category: "", subcategory: nil,
            accountId: "bank", targetAccountId: "loan"
        )
        await coordinator.updateForTransaction(pay, operation: .add(pay))

        // The tx must not move the loan balance (debt is driven by remainingPrincipal).
        #expect(coordinator.balances["loan"] == loanBalanceBefore)
        #expect(coordinator.balances["bank"] == 400_000)
    }
}
