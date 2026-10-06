//
//  LoanPaymentCurrencyTests.swift
//  TenraTests
//
//  Loan payments are recorded in the loan's currency, with the paying card as the
//  source leg. Two gaps let a foreign amount through unconverted:
//  - a card in another currency than the loan got no `convertedAmount`, so the
//    balance engine took the raw amount off it (a 100 USD payment as 100 ₸);
//  - the payment forms ignored the currency picked in the amount field, so 100 typed
//    as USD paid 100 ₸ off a KZT loan.
//
//  @MainActor + .sharedProcessState: conversion reads the process-global
//  CurrencyRateStore.shared, seeded per test and cleared in init (CLAUDE.md "Testing").
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct LoanPaymentCurrencyTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    /// 1 USD = 500 KZT, 1 EUR = 550 KZT.
    private func seedCache() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500, "EUR": 550],
            date: Date(),
            providerName: "test"
        ))
    }

    @Test("a payment from a card in another currency carries the card-currency amount")
    func paymentConvertsSourceLeg() throws {
        seedCache()
        let payment = Transaction(
            id: "p1", date: "2026-09-01", description: "", amount: 100, currency: "USD",
            type: .loanPayment, category: "", accountId: "card", targetAccountId: "loan"
        )

        let converted = try #require(LoansViewModel.convertingSourceLeg(payment, sourceCurrency: "KZT"))
        #expect(converted.convertedAmount == 50_000)
        #expect(converted.amount == 100)
        #expect(converted.currency == "USD")

        // The card is debited in tenge, not 100 ₸.
        let delta = BalanceCalculationEngine().contribution(
            of: converted,
            to: AccountBalance(accountId: "card", currentBalance: 0, currency: "KZT"),
            policy: .allTime
        )
        #expect(delta == -50_000)

        // Same currency, or an unknown card: nothing to convert.
        #expect(LoansViewModel.convertingSourceLeg(payment, sourceCurrency: "USD") == payment)
        #expect(LoansViewModel.convertingSourceLeg(payment, sourceCurrency: nil) == payment)
    }

    @Test("no rate for the card's currency: no payment, principal untouched")
    func paymentWithoutRateIsRefused() async throws {
        // Cache cleared in init; convertSync never reaches the network.
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: RecurringStore(repository: repo))
        let accountsVM = AccountsViewModel(repository: repo)
        accountsVM.transactionStore = store
        accountsVM.balanceCoordinator = balance
        let loansVM = LoansViewModel(repository: repo, accountsViewModel: accountsVM)

        let info = LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 1_000, remainingPrincipal: 1_000,
            interestRateAnnual: 12, termMonths: 12,
            startDate: "2026-01-01", paymentDay: 1
        )
        accountsVM.addLoanAccount(
            Account(id: "loan", name: "Loan", currency: "USD", loanInfo: info,
                    initialBalance: 1_000, balance: 1_000)
        )
        // A currency no rate provider knows, so no cached or fetched table can convert it.
        await accountsVM.addAccount(name: "Card", initialBalance: 0, currency: "ZZZ")
        let card = try #require(accountsVM.accounts.first { $0.name == "Card" })
        let yesterday = DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )

        let payment = loansVM.makeManualPayment(
            accountId: "loan", amount: 100, date: yesterday, sourceAccountId: card.id
        )
        let repayment = loansVM.makeEarlyRepayment(
            accountId: "loan", amount: 100, date: yesterday, type: .reduceTerm, sourceAccountId: card.id
        )

        #expect(payment == nil)
        #expect(repayment == nil)
        #expect(accountsVM.getAccount(by: "loan")?.loanInfo?.remainingPrincipal == 1_000)
        _ = store
    }

    @Test("an amount typed in another currency is converted into the loan's currency")
    func formAmountInLoanCurrency() {
        seedCache()
        #expect(LoanPaymentService.amountInLoanCurrency(100, currency: "USD", loanCurrency: "KZT") == 50_000)
        #expect(LoanPaymentService.amountInLoanCurrency(100, currency: "KZT", loanCurrency: "KZT") == 100)
        // The field's currency before it is set: the loan's own.
        #expect(LoanPaymentService.amountInLoanCurrency(100, currency: "", loanCurrency: "KZT") == 100)
        #expect(LoanPaymentService.amountInLoanCurrency(100, currency: "ZZZ", loanCurrency: "KZT") == nil)
    }
}
