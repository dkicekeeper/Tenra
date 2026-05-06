//
//  LoanTransactionMatcherTests.swift
//  TenraTests
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct LoanTransactionMatcherTests {

    // MARK: - Helpers

    private func makeLoanAccount(
        monthlyPayment: Decimal = 340_000,
        startDate: String = "2021-06-15",
        currency: String = "KZT"
    ) -> Account {
        var account = Account(
            id: "loan-1",
            name: "Car Loan",
            currency: currency,
            balance: 10_000_000
        )
        account.loanInfo = LoanInfo(
            bankName: "Bank",
            loanType: .annuity,
            originalPrincipal: 20_000_000,
            remainingPrincipal: 10_000_000,
            interestRateAnnual: 12,
            termMonths: 60,
            startDate: startDate,
            monthlyPayment: monthlyPayment,
            paymentDay: 15,
            paymentsMade: 0
        )
        return account
    }

    private func makeTransaction(
        id: String = UUID().uuidString,
        date: String,
        amount: Double,
        type: TransactionType = .expense,
        category: String = "Auto",
        accountId: String = "acc-1",
        currency: String = "KZT"
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "Payment",
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            accountId: accountId
        )
    }

    // MARK: - findCandidates

    @Test func findCandidates_matchesExpensesWithinTolerance() {
        let loan = makeLoanAccount(monthlyPayment: 340_000, startDate: "2021-06-15")
        let transactions = [
            makeTransaction(date: "2021-07-15", amount: 340_000),
            makeTransaction(date: "2021-08-15", amount: 330_000),
            makeTransaction(date: "2021-09-15", amount: 200_000),
            makeTransaction(date: "2021-10-15", amount: 500_000),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(
            for: loan,
            in: transactions
        )

        #expect(candidates.count == 2)
        #expect(candidates[0].amount == 340_000)
        #expect(candidates[1].amount == 330_000)
    }

    @Test func findCandidates_excludesNonExpenses() {
        let loan = makeLoanAccount()
        let transactions = [
            makeTransaction(date: "2021-07-15", amount: 340_000, type: .income),
            makeTransaction(date: "2021-07-16", amount: 340_000, type: .loanPayment),
            makeTransaction(date: "2021-07-17", amount: 340_000, type: .expense),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].type == .expense)
    }

    @Test func findCandidates_excludesTransactionsOutsideLoanPeriod() {
        let loan = makeLoanAccount(startDate: "2021-06-15")
        let transactions = [
            makeTransaction(date: "2021-05-15", amount: 340_000),
            makeTransaction(date: "2021-07-15", amount: 340_000),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].date == "2021-07-15")
    }

    @Test func findCandidates_matchesDifferentCurrencyLoan() {
        let loan = makeLoanAccount(monthlyPayment: 340_000, currency: "KZT")
        let transactions = [
            makeTransaction(date: "2021-07-15", amount: 340_000, currency: "KZT"),
            makeTransaction(date: "2021-07-16", amount: 340_000, currency: "USD"),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].currency == "KZT")
    }

    @Test func findCandidates_sortsByDate() {
        let loan = makeLoanAccount()
        let transactions = [
            makeTransaction(date: "2021-09-15", amount: 340_000),
            makeTransaction(date: "2021-07-15", amount: 340_000),
            makeTransaction(date: "2021-08-15", amount: 340_000),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates[0].date == "2021-07-15")
        #expect(candidates[1].date == "2021-08-15")
        #expect(candidates[2].date == "2021-09-15")
    }
}
