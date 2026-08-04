//
//  InsightsMoneyBucketTests.swift
//  TenraTests
//
//  Pins the Insights type-classification rule to the canonical
//  `TransactionType.summaryContribution` (CLAUDE.md ⚠️ #11): loan payments are
//  expenses and deposit interest accrual is income in Insights too, exactly as on
//  the Home and History summary cards. Insights previously ran its own
//  `switch tx.type` matching only `.income`/`.expense`, which dropped both.
//
//  Also pins the synthetic "Loan Payment" category key used by the breakdowns.
//
//  Pure tests — no CoreData, no TransactionStore, no async.
//

import Testing
import Foundation
@testable import Tenra

@Suite("Insights Money Bucket")
struct InsightsMoneyBucketTests {

    private let currency = "KZT"

    private func makeTx(
        date: String,
        amount: Double,
        type: TransactionType,
        category: String = "Misc"
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "Test",
            amount: amount,
            currency: "KZT",
            convertedAmount: nil,
            type: type,
            category: category,
            subcategory: nil,
            accountId: "acc-1",
            accountName: "TestAccount",
            createdAt: 1_700_000_000
        )
    }

    // MARK: - Classification parity

    @Test("moneyBucket mirrors summaryContribution for every transaction type")
    func bucketMatchesCanonicalRule() {
        let allTypes: [TransactionType] = [
            .income, .expense, .internalTransfer, .depositTopUp,
            .depositWithdrawal, .depositInterestAccrual, .loanPayment, .loanEarlyRepayment
        ]
        for type in allTypes {
            let expected: InsightsService.MoneyBucket
            switch type.summaryContribution(isFuture: false) {
            case .income:  expected = .income
            case .expense: expected = .expense
            case .internalTransfer, .plannedExpense, .ignored: expected = .none
            }
            #expect(InsightsService.moneyBucket(type) == expected, "type: \(type.rawValue)")
        }
    }

    @Test("Loan payments are expenses, deposit interest is income")
    func loanAndInterestBuckets() {
        #expect(InsightsService.moneyBucket(.loanPayment) == .expense)
        #expect(InsightsService.moneyBucket(.loanEarlyRepayment) == .expense)
        #expect(InsightsService.moneyBucket(.depositInterestAccrual) == .income)
        #expect(InsightsService.moneyBucket(.internalTransfer) == .none)
        #expect(InsightsService.moneyBucket(.depositTopUp) == .none)
        #expect(InsightsService.moneyBucket(.depositWithdrawal) == .none)
    }

    // MARK: - Monthly totals

    @Test("computeMonthlyTotals counts loan payments and deposit interest")
    func monthlyTotalsIncludeLoanAndInterest() {
        let jan = "2026-01-15"
        let txs = [
            makeTx(date: jan, amount: 100_000, type: .income, category: "Salary"),
            makeTx(date: jan, amount: 5_000, type: .depositInterestAccrual, category: "Interest"),
            makeTx(date: jan, amount: 20_000, type: .expense, category: "Food"),
            makeTx(date: jan, amount: 30_000, type: .loanPayment, category: ""),
            makeTx(date: jan, amount: 10_000, type: .loanEarlyRepayment, category: ""),
            // Neither side of the ledger — must stay out of both totals.
            makeTx(date: jan, amount: 70_000, type: .internalTransfer, category: "Transfer"),
            makeTx(date: jan, amount: 40_000, type: .depositTopUp, category: "Deposit")
        ]

        let totals = InsightsService.computeMonthlyTotals(
            from: txs,
            from: utc(2026, 1, 1),
            to: utc(2026, 2, 1),
            baseCurrency: currency
        )

        #expect(totals.count == 1)
        #expect(totals[0].totalIncome == 105_000)
        #expect(totals[0].totalExpenses == 60_000)
    }

    // MARK: - Category grouping

    @Test("Loan payments group under the synthetic Loan Payment category")
    func loanPaymentsGetSyntheticCategory() {
        let jan = "2026-01-15"
        let txs = [
            makeTx(date: jan, amount: 20_000, type: .expense, category: "Food"),
            makeTx(date: jan, amount: 30_000, type: .loanPayment, category: ""),
            // Even a user-tagged loan payment stays out of the user category: the
            // store's category aggregates count `type == .expense` only (rule C-6),
            // so folding it in would desync Insights budgets from the Categories screen.
            makeTx(date: jan, amount: 5_000, type: .loanPayment, category: "Food")
        ]

        let totals = InsightsService.computeCategoryMonthTotals(
            from: txs,
            from: utc(2026, 1, 1),
            to: utc(2026, 2, 1),
            baseCurrency: currency
        )

        let byCategory = Dictionary(uniqueKeysWithValues: totals.map { ($0.categoryName, $0.totalExpenses) })
        #expect(byCategory["Food"] == 20_000)
        #expect(byCategory[TransactionType.loanPaymentCategoryName] == 35_000)
    }

    @Test("categoryKey maps loan and interest types only")
    func categoryKeyMapping() {
        let loan = makeTx(date: "2026-01-15", amount: 1, type: .loanPayment, category: "")
        let early = makeTx(date: "2026-01-15", amount: 1, type: .loanEarlyRepayment, category: "Food")
        let expense = makeTx(date: "2026-01-15", amount: 1, type: .expense, category: "Food")
        // Accruals store a LOCALIZED category string — the key must not depend on it.
        let interestEN = makeTx(date: "2026-01-15", amount: 1, type: .depositInterestAccrual, category: "Interest")
        let interestRU = makeTx(date: "2026-01-15", amount: 1, type: .depositInterestAccrual, category: "Проценты")
        let income = makeTx(date: "2026-01-15", amount: 1, type: .income, category: "Salary")

        #expect(InsightsService.categoryKey(for: loan) == TransactionType.loanPaymentCategoryName)
        #expect(InsightsService.categoryKey(for: early) == TransactionType.loanPaymentCategoryName)
        #expect(InsightsService.categoryKey(for: expense) == "Food")
        #expect(InsightsService.categoryKey(for: interestEN) == TransactionType.depositInterestCategoryName)
        #expect(InsightsService.categoryKey(for: interestRU) == TransactionType.depositInterestCategoryName)
        #expect(InsightsService.categoryKey(for: income) == "Salary")
    }

    // MARK: - Synthetic category presentation

    @Test("Synthetic categories carry an icon; user categories don't")
    func syntheticStyle() {
        #expect(InsightsService.syntheticCategoryStyle(for: TransactionType.loanPaymentCategoryName) != nil)
        #expect(InsightsService.syntheticCategoryStyle(for: TransactionType.depositInterestCategoryName) != nil)
        #expect(InsightsService.syntheticCategoryStyle(for: "Food") == nil)
    }

    @Test("Synthetic category labels are localized, user categories pass through")
    func categoryLabels() {
        let loanLabel = InsightsService.categoryLabel(for: TransactionType.loanPaymentCategoryName)
        let interestLabel = InsightsService.categoryLabel(for: TransactionType.depositInterestCategoryName)
        #expect(loanLabel != TransactionType.loanPaymentCategoryName)
        #expect(interestLabel != TransactionType.depositInterestCategoryName)
        #expect(InsightsService.categoryLabel(for: "Food") == "Food")
    }

    @Test("Synthetic categories drill down into accounts, not subcategories")
    func deepDiveGrouping() {
        #expect(InsightsService.DeepDiveGrouping.forCategory(TransactionType.loanPaymentCategoryName) == .loanAccount)
        #expect(InsightsService.DeepDiveGrouping.forCategory(TransactionType.depositInterestCategoryName) == .depositAccount)
        #expect(InsightsService.DeepDiveGrouping.forCategory("Food") == .subcategory)
    }

    // MARK: - Helpers

    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
