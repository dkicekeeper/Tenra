//
//  LoanFuturePaymentGuardTests.swift
//  TenraTests
//
//  M-3: a loan payment / early repayment reduces `loanInfo.remainingPrincipal`
//  synchronously, and the loan account balance derives from remainingPrincipal (C-3).
//  A future-dated payment would therefore reduce the debt BEFORE its date arrives,
//  while the source-bank leg stays future-gated — contradicting the realized-excludes-
//  future policy. Decision: loan payments cannot be dated in the future. These pin that
//  the view-model rejects a future-dated payment and leaves the principal untouched.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct LoanFuturePaymentGuardTests {

    // Returns the store too — AccountsViewModel holds it only weakly, so the test
    // must retain it for the duration or `accounts` (= transactionStore?.accounts) goes nil.
    private static func makeGraph() -> (LoansViewModel, AccountsViewModel, TransactionStore) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: recurring)
        let accountsVM = AccountsViewModel(repository: repo)
        accountsVM.transactionStore = store
        accountsVM.balanceCoordinator = balance
        let loansVM = LoansViewModel(repository: repo, accountsViewModel: accountsVM)
        return (loansVM, accountsVM, store)
    }

    private static func addLoan(_ accountsVM: AccountsViewModel) {
        let info = LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 1_000_000, remainingPrincipal: 1_000_000,
            interestRateAnnual: 12, termMonths: 12,
            startDate: "2026-01-01", paymentDay: 1
        )
        accountsVM.addLoanAccount(
            Account(id: "loan", name: "Loan", currency: "KZT", loanInfo: info,
                    initialBalance: 1_000_000, balance: 1_000_000)
        )
    }

    private static func futureDate() -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)
    }
    private static func pastDate() -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -5, to: Date())!)
    }

    private static func remaining(_ accountsVM: AccountsViewModel) -> Decimal? {
        accountsVM.getAccount(by: "loan")?.loanInfo?.remainingPrincipal
    }

    @Test("future-dated manual payment is rejected and leaves principal untouched")
    func futureManualPaymentRejected() {
        let (loansVM, accountsVM, store) = Self.makeGraph()
        _ = store
        Self.addLoan(accountsVM)
        let result = loansVM.makeManualPayment(
            accountId: "loan", amount: 50_000, date: Self.futureDate(), sourceAccountId: "bank"
        )
        #expect(result == nil)
        #expect(Self.remaining(accountsVM) == 1_000_000)
    }

    @Test("past-dated manual payment is accepted and reduces principal")
    func pastManualPaymentAccepted() {
        let (loansVM, accountsVM, store) = Self.makeGraph()
        _ = store
        Self.addLoan(accountsVM)
        let result = loansVM.makeManualPayment(
            accountId: "loan", amount: 50_000, date: Self.pastDate(), sourceAccountId: "bank"
        )
        #expect(result != nil)
        #expect((Self.remaining(accountsVM) ?? .greatestFiniteMagnitude) < 1_000_000)
    }

    @Test("future-dated early repayment is rejected and leaves principal untouched")
    func futureEarlyRepaymentRejected() {
        let (loansVM, accountsVM, store) = Self.makeGraph()
        _ = store
        Self.addLoan(accountsVM)
        let result = loansVM.makeEarlyRepayment(
            accountId: "loan", amount: 100_000, date: Self.futureDate(),
            type: .reduceTerm, sourceAccountId: "bank"
        )
        #expect(result == nil)
        #expect(Self.remaining(accountsVM) == 1_000_000)
    }
}
