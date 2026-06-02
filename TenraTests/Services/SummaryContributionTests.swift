//
//  SummaryContributionTests.swift
//  TenraTests
//
//  Pins the SINGLE transaction→summary classification rule shared by every summary
//  path (SummaryCalculator / TransactionQueryService), so they cannot diverge.
//

import Testing
@testable import Tenra

struct SummaryContributionTests {

    @Test("realized income and deposit interest both count as income")
    func realizedIncome() {
        #expect(TransactionType.income.summaryContribution(isFuture: false) == .income)
        // Deposit interest accrual is realized income to the user — counts as income,
        // NOT excluded. This is the unification: every summary path agrees on it.
        #expect(TransactionType.depositInterestAccrual.summaryContribution(isFuture: false) == .income)
    }

    @Test("realized expense and loan payments count as expense")
    func realizedExpense() {
        #expect(TransactionType.expense.summaryContribution(isFuture: false) == .expense)
        #expect(TransactionType.loanPayment.summaryContribution(isFuture: false) == .expense)
        #expect(TransactionType.loanEarlyRepayment.summaryContribution(isFuture: false) == .expense)
    }

    @Test("realized internal transfer is its own bucket; deposit top-up/withdrawal are ignored")
    func realizedTransferAndDepositMoves() {
        #expect(TransactionType.internalTransfer.summaryContribution(isFuture: false) == .internalTransfer)
        #expect(TransactionType.depositTopUp.summaryContribution(isFuture: false) == .ignored)
        #expect(TransactionType.depositWithdrawal.summaryContribution(isFuture: false) == .ignored)
    }

    @Test("future expense and loan payment become planned; everything else future is ignored")
    func futureBuckets() {
        #expect(TransactionType.expense.summaryContribution(isFuture: true) == .plannedExpense)
        #expect(TransactionType.loanPayment.summaryContribution(isFuture: true) == .plannedExpense)
        #expect(TransactionType.income.summaryContribution(isFuture: true) == .ignored)
        #expect(TransactionType.depositInterestAccrual.summaryContribution(isFuture: true) == .ignored)
        #expect(TransactionType.internalTransfer.summaryContribution(isFuture: true) == .ignored)
        #expect(TransactionType.loanEarlyRepayment.summaryContribution(isFuture: true) == .ignored)
    }
}
