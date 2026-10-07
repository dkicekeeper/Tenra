//
//  LoanPaymentRollbackTests.swift
//  TenraTests
//
//  Deleting a loan payment takes its effect off the loan. The loan's state (remaining
//  principal, interest paid, payments made, last payment date, early repayments) is
//  written when a payment is recorded, and nothing undid it on delete: the debt stayed
//  reduced (the loan's balance is its remaining principal) and the month kept showing
//  "Paid". Pins `LoanPaymentService.reversingPayment` and the store hook that runs it on
//  every delete (`TransactionStore+LoanPayments`).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct LoanPaymentRollbackTests {

    // MARK: - Pure reversal

    /// 1 000 000 at 12% (1% a month) over 12 months.
    private var annuity: LoanInfo {
        LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 1_000_000, interestRateAnnual: 12,
            termMonths: 12, startDate: "2026-01-01", paymentDay: 1
        )
    }

    private var annuityAccount: Account {
        Account(id: "loan", name: "Loan", currency: "KZT", loanInfo: annuity)
    }

    private func recorded(_ transaction: Transaction) -> LoanPaymentService.RecordedPayment {
        LoanPaymentService.recordedPayment(
            transaction, loanCurrency: "KZT", sourceCurrency: nil, rates: RateSnapshot(rates: [:])
        )
    }

    /// Two 100 000 payments: 10 000 interest + 90 000 principal, then 9 100 + 90 900.
    private func twoPayments() -> (first: Transaction, afterFirst: LoanInfo, second: Transaction, afterBoth: LoanInfo) {
        let (first, afterFirst) = LoanPaymentService.createManualPayment(
            account: annuityAccount, loanInfo: annuity, paymentAmount: 100_000,
            dateStr: "2026-09-15", sourceAccountId: "bank", sourceAccountName: nil
        )
        let (second, afterBoth) = LoanPaymentService.createManualPayment(
            account: annuityAccount, loanInfo: afterFirst, paymentAmount: 100_000,
            dateStr: "2026-10-03", sourceAccountId: "bank", sourceAccountName: nil
        )
        return (first, afterFirst, second, afterBoth)
    }

    @Test func deletingTheLatestPaymentRestoresTheLoanAsItWasBefore() {
        let (first, afterFirst, second, afterBoth) = twoPayments()
        #expect(afterBoth.remainingPrincipal == 819_100)
        #expect(afterBoth.totalInterestPaid == 19_100)

        let rolledBack = LoanPaymentService.reversingPayment(
            recorded(second), in: afterBoth, otherPayments: [recorded(first)]
        )
        // Principal, interest paid, payments made and the last payment date all come back.
        #expect(rolledBack == afterFirst)
        #expect(rolledBack.lastPaymentDate == "2026-09-15")
    }

    @Test func deletingAnOlderPaymentTakesOffOnlyItsOwnShare() {
        let (first, _, second, afterBoth) = twoPayments()
        // The later payment is undone first to find what was owed when the first was made
        // (1 000 000): its interest was 10 000, its principal 90 000.
        let rolledBack = LoanPaymentService.reversingPayment(
            recorded(first), in: afterBoth, otherPayments: [recorded(second)]
        )
        #expect(rolledBack.remainingPrincipal == 909_100)
        #expect(rolledBack.totalInterestPaid == 9_100)
        #expect(rolledBack.paymentsMade == 1)
        // The later payment wrote the last payment date; it stays.
        #expect(rolledBack.lastPaymentDate == "2026-10-03")
    }

    @Test func deletingEveryPaymentLeavesNothingPaid() throws {
        let (first, _, second, afterBoth) = twoPayments()
        let once = LoanPaymentService.reversingPayment(recorded(second), in: afterBoth, otherPayments: [recorded(first)])
        let twice = LoanPaymentService.reversingPayment(recorded(first), in: once, otherPayments: [])
        #expect(twice.remainingPrincipal == 1_000_000)
        #expect(twice.totalInterestPaid == 0)
        #expect(twice.paymentsMade == 0)
        #expect(twice.lastPaymentDate == nil)
    }

    @Test func lastPaymentDateFallsBackToAMarkedScheduleRow() {
        let (_, _, second, afterBoth) = twoPayments()
        var marked = afterBoth
        marked.markedPaidThrough = "2026-08-01"
        let rolledBack = LoanPaymentService.reversingPayment(recorded(second), in: marked, otherPayments: [])
        #expect(rolledBack.lastPaymentDate == "2026-08-01")
        #expect(rolledBack.markedPaidThrough == "2026-08-01")
    }

    @Test func principalNeverGoesAboveTheOriginal() {
        // "Mark as unpaid" on the first row already reset everything; deleting a payment
        // afterwards must not add its principal back a second time.
        let (first, _, second, afterBoth) = twoPayments()
        var reset = afterBoth
        reset.remainingPrincipal = 1_000_000
        reset.paymentsMade = 0
        reset.totalInterestPaid = 0
        let rolledBack = LoanPaymentService.reversingPayment(recorded(second), in: reset, otherPayments: [recorded(first)])
        #expect(rolledBack.remainingPrincipal == 1_000_000)
        #expect(rolledBack.paymentsMade == 0)
        #expect(rolledBack.totalInterestPaid == 0)
    }

    @Test func deletingTheFinalInstallmentReopensTheLoan() {
        let installment = LoanInfo(
            bankName: "B", loanType: .installment,
            originalPrincipal: 600_000, remainingPrincipal: 50_000,
            termMonths: 12, startDate: "2026-01-10", monthlyPayment: 50_000,
            paymentDay: 15, paymentsMade: 11
        )
        let account = Account(id: "loan", name: "Loan", currency: "KZT", loanInfo: installment)
        let (last, paidOff) = LoanPaymentService.createManualPayment(
            account: account, loanInfo: installment, paymentAmount: 50_000,
            dateStr: "2026-10-03", sourceAccountId: "bank", sourceAccountName: nil
        )
        #expect(paidOff.isPaidOff)

        let rolledBack = LoanPaymentService.reversingPayment(recorded(last), in: paidOff, otherPayments: [])
        #expect(rolledBack.remainingPrincipal == 50_000)
        #expect(!rolledBack.isPaidOff)
        #expect(rolledBack.paymentsMade == 11)
    }

    @Test func deletingAnEarlyRepaymentRestoresTermPaymentAndSchedule() {
        let (first, _, second, afterBoth) = twoPayments()
        for type in [EarlyRepaymentType.reduceTerm, .reducePayment] {
            let (repayment, repaid) = LoanPaymentService.createEarlyRepaymentTransaction(
                account: annuityAccount, loanInfo: afterBoth, amount: 200_000,
                date: "2026-10-04", type: type, sourceAccountId: "bank", sourceAccountName: nil
            )
            #expect(repaid.earlyRepayments.count == 1)
            #expect(repaid.termMonths != afterBoth.termMonths || repaid.monthlyPayment != afterBoth.monthlyPayment)

            let rolledBack = LoanPaymentService.reversingPayment(
                recorded(repayment), in: repaid, otherPayments: [recorded(first), recorded(second)]
            )
            // Principal, the schedule entry, and the term (with the end date) or the payment.
            #expect(rolledBack == afterBoth, "\(type)")
        }
    }

    @Test func olderReduceTermEntryWithoutTheTermBeforeIsRecomputed() {
        // Recorded before termBefore existed: the term is recomputed from the restored
        // principal at the current payment, which gives the original 12 months back here.
        let (_, _, _, afterBoth) = twoPayments()
        var repaid = afterBoth
        repaid.remainingPrincipal -= 200_000
        repaid.earlyRepayments = [EarlyRepayment(date: "2026-10-04", amount: 200_000, type: .reduceTerm)]
        repaid.termMonths = 9
        let deleted = LoanPaymentService.RecordedPayment(type: .loanEarlyRepayment, date: "2026-10-04", amount: 200_000)

        let rolledBack = LoanPaymentService.reversingPayment(deleted, in: repaid, otherPayments: [])
        #expect(rolledBack.remainingPrincipal == afterBoth.remainingPrincipal)
        #expect(rolledBack.earlyRepayments.isEmpty)
        #expect(rolledBack.termMonths == 12)
        #expect(rolledBack.endDate == afterBoth.endDate)
    }

    @Test func deletingAnEarlierReducePaymentHandsItsPaymentToTheNextOne() {
        let (_, _, _, afterBoth) = twoPayments()
        let (firstRepayment, once) = LoanPaymentService.createEarlyRepaymentTransaction(
            account: annuityAccount, loanInfo: afterBoth, amount: 100_000,
            date: "2026-10-04", type: .reducePayment, sourceAccountId: "bank", sourceAccountName: nil
        )
        let (secondRepayment, twice) = LoanPaymentService.createEarlyRepaymentTransaction(
            account: annuityAccount, loanInfo: once, amount: 100_000,
            date: "2026-10-05", type: .reducePayment, sourceAccountId: "bank", sourceAccountName: nil
        )

        let rolledBack = LoanPaymentService.reversingPayment(
            recorded(firstRepayment), in: twice, otherPayments: [recorded(secondRepayment)]
        )
        #expect(rolledBack.remainingPrincipal == twice.remainingPrincipal + 100_000)
        #expect(rolledBack.earlyRepayments.count == 1)
        // The schedule replays the original payment up to the remaining repayment.
        #expect(rolledBack.earlyRepayments.first?.paymentBefore == afterBoth.monthlyPayment)
        // The payment now in force is re-planned from the restored principal.
        #expect(rolledBack.monthlyPayment == once.monthlyPayment)
    }

    // MARK: - Stored fields

    @Test func newFieldsRoundTripAndOlderJSONDecodes() throws {
        var info = annuity
        info.markedPaidThrough = "2026-10-01"
        let decoded = try JSONDecoder().decode(LoanInfo.self, from: JSONEncoder().encode(info))
        #expect(decoded.markedPaidThrough == "2026-10-01")
        let unmarked = try String(decoding: JSONEncoder().encode(annuity), as: UTF8.self)
        #expect(!unmarked.contains("markedPaidThrough"))

        let olderEntry = Data(#"{"date":"2026-10-04","amount":100,"type":"reduce_term"}"#.utf8)
        let entry = try JSONDecoder().decode(EarlyRepayment.self, from: olderEntry)
        #expect(entry.termBefore == nil)
        #expect(entry.paymentBefore == nil)
    }

    // MARK: - Through the store

    /// The view-model graph a loan payment goes through, on an isolated repository. Holds
    /// the store: AccountsViewModel keeps it weakly.
    @MainActor
    private struct Graph {
        let store: TransactionStore
        let balance: BalanceCoordinator
        let accounts: AccountsViewModel
        let loans: LoansViewModel

        var loanInfo: LoanInfo? { store.accountById["loan"]?.loanInfo }
    }

    /// A 1 000 000 annuity at 12% that started two months ago (this month is payment #2)
    /// and a KZT card holding 1 000 000.
    private func makeGraph() async -> (Graph, LoanInfo) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.loanRollback.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: RecurringStore(repository: repo))
        let accounts = AccountsViewModel(repository: repo)
        accounts.transactionStore = store
        accounts.balanceCoordinator = balance
        let loans = LoansViewModel(repository: repo, accountsViewModel: accounts)

        let calendar = FastDateParser.calendar
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let start = calendar.date(byAdding: .month, value: -2, to: thisMonth)!
        let info = LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 1_000_000, interestRateAnnual: 12,
            termMonths: 12, startDate: FastDateParser.string(from: start), paymentDay: 28
        )
        store.accounts = [
            Account(id: "bank", name: "Card", currency: "KZT", initialBalance: 1_000_000),
            Account(id: "loan", name: "Loan", currency: "KZT", loanInfo: info, initialBalance: 1_000_000, balance: 1_000_000),
        ]
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)
        return (Graph(store: store, balance: balance, accounts: accounts, loans: loans), info)
    }

    private var today: String { FastDateParser.string(from: Date()) }

    /// Waits, at most 2 s, for `condition`. `updateLoan` moves the loan's balance in a Task.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func monthStatus(_ graph: Graph) -> LoanMonthStatus? {
        guard let loan = graph.store.accountById["loan"] else { return nil }
        return LoanMonthStatusService.status(
            loan: loan,
            loanTransactions: graph.store.transactionsByAccount["loan"] ?? [],
            today: Date(),
            rates: RateSnapshot(rates: [:])
        )
    }

    @Test func deletingAPaymentRollsBackTheLoanItsBalanceAndTheMonth() async throws {
        let (graph, original) = await makeGraph()
        let payment = try #require(graph.loans.makeManualPayment(
            accountId: "loan", amount: 100_000, date: today, sourceAccountId: "bank"
        ))
        _ = try await graph.store.add(payment)
        let reduced = try #require(graph.loanInfo)
        #expect(reduced.remainingPrincipal == 910_000) // 100 000 = 10 000 interest + 90 000
        #expect(reduced.lastPaymentDate == today)
        let reducedDebt = NSDecimalNumber(decimal: reduced.remainingPrincipal).doubleValue
        await waitUntil { graph.balance.balances["loan"] == reducedDebt }
        if case .paid = monthStatus(graph) {} else { Issue.record("the payment covers the month") }

        try await graph.store.delete(payment)

        #expect(graph.loanInfo == original)
        // The loan's balance is its remaining principal; the card gets its money back.
        #expect(graph.balance.balances["loan"] == 1_000_000)
        #expect(graph.balance.balances["bank"] == 1_000_000)
        if case .unpaid = monthStatus(graph) {} else { Issue.record("the month is unpaid again") }
    }

    @Test func deletingAnEarlyRepaymentRestoresTheTermAndTheSchedule() async throws {
        let (graph, original) = await makeGraph()
        let repayment = try #require(graph.loans.makeEarlyRepayment(
            accountId: "loan", amount: 300_000, date: today, type: .reduceTerm, sourceAccountId: "bank"
        ))
        _ = try await graph.store.add(repayment)
        let repaid = try #require(graph.loanInfo)
        #expect(repaid.termMonths < original.termMonths)
        #expect(repaid.earlyRepayments.count == 1)
        let repaidDebt = NSDecimalNumber(decimal: repaid.remainingPrincipal).doubleValue
        await waitUntil { graph.balance.balances["loan"] == repaidDebt }

        try await graph.store.delete(repayment)

        #expect(graph.loanInfo == original)
        #expect(graph.balance.balances["loan"] == 1_000_000)
    }

    @Test func deletingTheCardsTransactionsRollsBackItsLoanPayments() async throws {
        let (graph, original) = await makeGraph()
        let payment = try #require(graph.loans.makeManualPayment(
            accountId: "loan", amount: 100_000, date: today, sourceAccountId: "bank"
        ))
        _ = try await graph.store.add(payment)
        let reducedDebt = NSDecimalNumber(decimal: graph.loanInfo?.remainingPrincipal ?? 0).doubleValue
        await waitUntil { graph.balance.balances["loan"] == reducedDebt }

        // "Delete account and its transactions" on the card.
        await graph.store.deleteTransactions(forAccountId: "bank")

        #expect(graph.loanInfo == original)
        #expect(graph.balance.balances["loan"] == 1_000_000)
    }

    @Test func markAsPaidSurvivesADeletedPayment() async throws {
        let (graph, _) = await makeGraph()
        // Row #2 is this month: paid outside the app.
        graph.loans.markPaymentsPaid(accountId: "loan", upToPaymentNumber: 2)
        let marked = try #require(graph.loanInfo)
        let markedRow = try #require(marked.markedPaidThrough)
        await waitUntil {
            graph.balance.balances["loan"] == NSDecimalNumber(decimal: marked.remainingPrincipal).doubleValue
        }

        let payment = try #require(graph.loans.makeManualPayment(
            accountId: "loan", amount: 100_000, date: today, sourceAccountId: "bank"
        ))
        _ = try await graph.store.add(payment)
        let paidDebt = NSDecimalNumber(decimal: graph.loanInfo?.remainingPrincipal ?? 0).doubleValue
        await waitUntil { graph.balance.balances["loan"] == paidDebt }

        try await graph.store.delete(payment)

        let rolledBack = try #require(graph.loanInfo)
        #expect(rolledBack.remainingPrincipal == marked.remainingPrincipal)
        #expect(rolledBack.paymentsMade == 2)
        #expect(rolledBack.markedPaidThrough == markedRow)
        #expect(rolledBack.lastPaymentDate == markedRow)
        if case .paid = monthStatus(graph) {} else { Issue.record("the marked month stays paid") }
    }

    @Test func anotherLoansPaymentLeavesThisLoanAlone() async throws {
        let (graph, _) = await makeGraph()
        let other = LoanInfo(
            bankName: "B", loanType: .installment,
            originalPrincipal: 120_000, termMonths: 12, startDate: "2026-01-10", paymentDay: 15
        )
        graph.store.accounts.append(Account(id: "other", name: "Other", currency: "KZT", loanInfo: other, initialBalance: 120_000, balance: 120_000))
        graph.store.rebuildAccountById()
        await graph.balance.registerAccounts(graph.store.accounts)

        let payment = try #require(graph.loans.makeManualPayment(
            accountId: "loan", amount: 100_000, date: today, sourceAccountId: "bank"
        ))
        _ = try await graph.store.add(payment)
        let otherPayment = try #require(graph.loans.makeManualPayment(
            accountId: "other", amount: 10_000, date: today, sourceAccountId: "bank"
        ))
        _ = try await graph.store.add(otherPayment)
        let before = graph.loanInfo

        try await graph.store.delete(otherPayment)

        #expect(graph.loanInfo == before)
        #expect(graph.store.accountById["other"]?.loanInfo?.remainingPrincipal == 120_000)
    }
}
