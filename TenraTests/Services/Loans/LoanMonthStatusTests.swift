//
//  LoanMonthStatusTests.swift
//  TenraTests
//
//  "Paid this month" / "Not paid" on the loans list and loan screen, and the unpaid total
//  in the loans summary. Pins what counts as this month's regular payment (a .loanPayment
//  to the loan dated from the 1st through today, or the loan's lastPaymentDate, which
//  "Mark as paid" in the schedule writes), which loans show no status, the due dates, and
//  the base-currency sum.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct LoanMonthStatusTests {

    // MARK: - Helpers

    /// "yyyy-MM-dd" → local midnight in the calendar the service reads dates with.
    private func day(_ key: String) -> Date {
        FastDateParser.date(from: key)!
    }

    /// Installment by default: 50 000 a month on the 15th, 12 months from 10 Jan 2026, so
    /// October 2026 is payment #9.
    private func loan(
        id: String = "loan",
        currency: String = "KZT",
        remaining: Decimal = 500_000,
        rate: Decimal = 0,
        monthlyPayment: Decimal = 50_000,
        startDate: String = "2026-01-10",
        termMonths: Int = 12,
        paymentDay: Int = 15,
        lastPaymentDate: String? = nil
    ) -> Account {
        Account(
            id: id,
            name: "Loan \(id)",
            currency: currency,
            loanInfo: LoanInfo(
                bankName: "Bank",
                loanType: rate > 0 ? .annuity : .installment,
                originalPrincipal: 600_000,
                remainingPrincipal: remaining,
                interestRateAnnual: rate,
                termMonths: termMonths,
                startDate: startDate,
                monthlyPayment: monthlyPayment,
                paymentDay: paymentDay,
                lastPaymentDate: lastPaymentDate
            )
        )
    }

    /// Orientation contract: accountId = source bank, targetAccountId = loan.
    private func payment(
        _ date: String,
        loanId: String = "loan",
        type: TransactionType = .loanPayment,
        amount: Double = 50_000
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "",
            amount: amount,
            currency: "KZT",
            type: type,
            category: "",
            accountId: "bank",
            targetAccountId: loanId
        )
    }

    /// Every test runs on 6 October 2026 unless it passes another day.
    private func status(_ loan: Account, _ transactions: [Transaction] = [], today: String = "2026-10-06") -> LoanMonthStatus? {
        LoanMonthStatusService.status(loan: loan, loanTransactions: transactions, today: day(today))
    }

    // MARK: - Paid / unpaid

    @Test func loanPaymentThisMonthIsPaid() {
        let result = status(loan(), [payment("2026-10-03")])
        #expect(result == LoanMonthStatus.paid(nextDueDate: day("2026-11-15")))
        #expect(result?.nextDueDate == day("2026-11-15"))
    }

    @Test func markedPaidInTheScheduleIsPaid() {
        // "Mark as paid" writes the schedule row's date to lastPaymentDate, no transaction.
        #expect(status(loan(lastPaymentDate: "2026-10-10")) == LoanMonthStatus.paid(nextDueDate: day("2026-11-15")))
    }

    @Test func noPaymentIsUnpaidWithThisMonthsDueDate() {
        let result = status(loan())
        #expect(result == LoanMonthStatus.unpaid(dueDate: day("2026-10-15"), isOverdue: false))
        #expect(result?.nextDueDate == day("2026-10-15"))
    }

    @Test func unpaidIsOverdueOnlyAfterTheDueDate() {
        #expect(status(loan(paymentDay: 5)) == LoanMonthStatus.unpaid(dueDate: day("2026-10-05"), isOverdue: true))
        #expect(status(loan(paymentDay: 6)) == LoanMonthStatus.unpaid(dueDate: day("2026-10-06"), isOverdue: false))
    }

    @Test func paymentLastMonthOnlyIsUnpaid() {
        let result = status(loan(lastPaymentDate: "2026-09-28"), [payment("2026-09-28")])
        #expect(result == LoanMonthStatus.unpaid(dueDate: day("2026-10-15"), isOverdue: false))
    }

    @Test func earlyRepaymentAloneIsUnpaid() {
        // An early repayment shortens the term or lowers the payment; it is not the month's
        // regular payment, and it does not move lastPaymentDate.
        let result = status(
            loan(lastPaymentDate: "2026-09-15"),
            [payment("2026-10-02", type: .loanEarlyRepayment, amount: 200_000)]
        )
        #expect(result == LoanMonthStatus.unpaid(dueDate: day("2026-10-15"), isOverdue: false))
    }

    @Test func futureDatedOrOtherLoansPaymentsDoNotCount() {
        let result = status(loan(), [
            payment("2026-10-20"),                  // later this month: not realized yet
            payment("2026-10-03", loanId: "other"), // another loan's payment
        ])
        #expect(result == LoanMonthStatus.unpaid(dueDate: day("2026-10-15"), isOverdue: false))
    }

    @Test func paymentDayIsClampedToEachMonth() {
        let account = loan(termMonths: 24, paymentDay: 31)
        #expect(status(account, today: "2026-11-06") == LoanMonthStatus.unpaid(dueDate: day("2026-11-30"), isOverdue: false))
        #expect(status(account, [payment("2026-11-02")], today: "2026-11-06") == LoanMonthStatus.paid(nextDueDate: day("2026-12-31")))
        #expect(status(account, today: "2027-02-03") == LoanMonthStatus.unpaid(dueDate: day("2027-02-28"), isOverdue: false))
    }

    // MARK: - No status

    @Test func paidOffLoanHasNoStatus() {
        #expect(status(loan(remaining: 0)) == nil)
        #expect(status(loan(remaining: 0), [payment("2026-10-03")]) == nil)
    }

    @Test func loanNotStartedYetHasNoStatus() {
        // Payment #1 falls the month after the start month (schedule: startDate + 1 month).
        #expect(status(loan(startDate: "2026-10-02")) == nil)
        #expect(status(loan(startDate: "2026-12-01")) == nil)
        #expect(status(loan(startDate: "2026-09-20")) == LoanMonthStatus.unpaid(dueDate: day("2026-10-15"), isOverdue: false))
    }

    @Test func loanPastItsLastScheduledMonthHasNoStatus() {
        // 12 payments, October 2025 to September 2026.
        #expect(status(loan(startDate: "2025-09-10")) == nil)
        // 12 payments, November 2025 to October 2026: October is the last one.
        #expect(status(loan(startDate: "2025-10-10")) == LoanMonthStatus.unpaid(dueDate: day("2026-10-15"), isOverdue: false))
    }

    // MARK: - Unpaid total

    @Test func unpaidTotalSumsUnpaidLoansInTheBaseCurrency() {
        let loans = [
            loan(id: "kzt", monthlyPayment: 100_000),
            loan(id: "usd", currency: "USD", remaining: 5_000, monthlyPayment: 200),
            loan(id: "paid", monthlyPayment: 70_000),
            loan(id: "closed", remaining: 0, monthlyPayment: 30_000),
        ]
        var statuses: [String: LoanMonthStatus] = [:]
        for account in loans {
            let transactions = account.id == "paid" ? [payment("2026-10-01", loanId: "paid")] : []
            statuses[account.id] = status(account, transactions)
        }
        #expect(statuses["paid"] == LoanMonthStatus.paid(nextDueDate: day("2026-11-15")))
        #expect(statuses["closed"] == nil)

        let rates = RateSnapshot(rates: ["USD": 500]) // 1 USD = 500 KZT
        // 100 000 KZT + 200 USD × 500; the paid and the closed loan add nothing.
        #expect(LoanMonthStatusService.unpaidTotal(loans: loans, statuses: statuses, baseCurrency: "KZT", rates: rates) == 200_000)
        #expect(LoanMonthStatusService.unpaidTotal(loans: loans, statuses: statuses, baseCurrency: "USD", rates: rates) == 400)
    }

    @Test func unpaidTotalWithAMissingRateFallsBackToTheUnconvertedAmount() {
        let eur = loan(id: "eur", currency: "EUR", monthlyPayment: 300)
        var statuses: [String: LoanMonthStatus] = [:]
        statuses["eur"] = status(eur)
        let total = LoanMonthStatusService.unpaidTotal(
            loans: [eur], statuses: statuses, baseCurrency: "KZT", rates: RateSnapshot(rates: [:])
        )
        #expect(total == 300)
    }

    // MARK: - Summary totals

    @Test func summaryTotalsConvertOnlyWhenLoanCurrenciesDiffer() {
        let rates = RateSnapshot(rates: ["USD": 500]) // 1 USD = 500 KZT

        // One currency: summed in it, whatever the base currency.
        let dollars = [
            loan(id: "a", currency: "USD", remaining: 5_000, monthlyPayment: 200),
            loan(id: "b", currency: "USD", remaining: 1_000, monthlyPayment: 100),
        ]
        let same = LoanMonthStatusService.summaryTotals(loans: dollars, baseCurrency: "KZT", rates: rates)
        #expect(same.currency == "USD")
        #expect(same.debt == 6_000)
        #expect(same.monthly == 300)

        // Several: each loan in the base currency first, not 500 000 + 5 000 = 505 000.
        let mixed = [loan(id: "kzt"), loan(id: "usd", currency: "USD", remaining: 5_000, monthlyPayment: 200)]
        let converted = LoanMonthStatusService.summaryTotals(loans: mixed, baseCurrency: "KZT", rates: rates)
        #expect(converted.currency == "KZT")
        #expect(converted.debt == 3_000_000)   // 500 000 + 5 000 × 500
        #expect(converted.monthly == 150_000)  // 50 000 + 200 × 500

        #expect(LoanMonthStatusService.summaryTotals(loans: [], baseCurrency: "KZT", rates: rates).currency == nil)
    }

    @Test func amountDueIsCappedAtWhatIsLeftToRepay() throws {
        // Regular month: the monthly payment.
        let regular = try #require(loan().loanInfo)
        #expect(LoanMonthStatusService.amountDue(regular) == 50_000)
        // Final month of an installment: only the 12 000 left.
        let lastInstallment = try #require(loan(remaining: 12_000).loanInfo)
        #expect(LoanMonthStatusService.amountDue(lastInstallment) == 12_000)
        // Final month of a 12% annuity: the 12 000 left plus the month's interest (120).
        let lastAnnuity = try #require(loan(remaining: 12_000, rate: 12).loanInfo)
        #expect(LoanMonthStatusService.amountDue(lastAnnuity) == 12_120)
    }
}
