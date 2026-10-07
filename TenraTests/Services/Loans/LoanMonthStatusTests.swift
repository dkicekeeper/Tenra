//
//  LoanMonthStatusTests.swift
//  TenraTests
//
//  "Paid this month" / "Not paid" on the loans list and loan screen, and the unpaid total
//  in the loans summary. Pins what makes a month paid (this month's payments to the loan,
//  regular and early, dated from the 1st through today and converted into the loan's
//  currency, adding up to the month's amount due; or "Mark as paid" in the schedule), what
//  is left to pay after partial payments, which loans show no status, the due dates, and
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
        lastPaymentDate: String? = nil,
        markedPaidThrough: String? = nil
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
                lastPaymentDate: lastPaymentDate,
                markedPaidThrough: markedPaidThrough
            )
        )
    }

    /// Orientation contract: accountId = source bank, targetAccountId = loan.
    private func payment(
        _ date: String,
        loanId: String = "loan",
        type: TransactionType = .loanPayment,
        amount: Double = 50_000,
        currency: String = "KZT",
        convertedAmount: Double? = nil,
        targetCurrency: String? = nil,
        targetAmount: Double? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "",
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: type,
            category: "",
            accountId: "bank",
            targetAccountId: loanId,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount
        )
    }

    /// Every test runs on 6 October 2026 unless it passes another day. No rates unless
    /// passed: a payment in the loan's currency needs none.
    private func status(
        _ loan: Account,
        _ transactions: [Transaction] = [],
        today: String = "2026-10-06",
        rates: [String: Double] = [:],
        accounts: [String: Account] = [:]
    ) -> LoanMonthStatus? {
        LoanMonthStatusService.status(
            loan: loan,
            loanTransactions: transactions,
            today: day(today),
            rates: RateSnapshot(rates: rates),
            accountsById: accounts
        )
    }

    private var paidInOctober: LoanMonthStatus {
        .paid(nextDueDate: day("2026-11-15"))
    }

    private func unpaidInOctober(leftToPay: Double) -> LoanMonthStatus {
        .unpaid(dueDate: day("2026-10-15"), isOverdue: false, leftToPay: leftToPay)
    }

    // MARK: - Paid / unpaid by the sum of this month's payments

    @Test func paymentOfExactlyTheAmountDueIsPaid() {
        let result = status(loan(), [payment("2026-10-03")])
        #expect(result == paidInOctober)
        #expect(result?.nextDueDate == day("2026-11-15"))
    }

    @Test func paymentAboveTheAmountDueIsPaid() {
        #expect(status(loan(), [payment("2026-10-03", amount: 60_000)]) == paidInOctober)
    }

    @Test func partialPaymentIsUnpaidWithTheRestLeftToPay() {
        // The owner's rule: one operation is not enough, the month's payments must add up
        // to the monthly payment.
        let result = status(loan(), [payment("2026-10-03", amount: 30_000)])
        #expect(result == unpaidInOctober(leftToPay: 20_000))
        #expect(result?.nextDueDate == day("2026-10-15"))
    }

    @Test func twoPartialPaymentsThatAddUpArePaid() {
        let partials = [payment("2026-10-01", amount: 20_000), payment("2026-10-05", amount: 30_000)]
        #expect(status(loan(), partials) == paidInOctober)
    }

    @Test func earlyRepaymentCountsTowardTheMonth() {
        // Every payment operation to the loan counts, an early repayment too.
        let alone = [payment("2026-10-02", type: .loanEarlyRepayment, amount: 200_000)]
        #expect(status(loan(), alone) == paidInOctober)
        let withRegular = [
            payment("2026-10-02", type: .loanEarlyRepayment, amount: 10_000),
            payment("2026-10-04", amount: 40_000),
        ]
        #expect(status(loan(), withRegular) == paidInOctober)
    }

    @Test func noPaymentIsUnpaidWithThisMonthsDueDate() {
        let result = status(loan())
        #expect(result == unpaidInOctober(leftToPay: 50_000))
        #expect(result?.nextDueDate == day("2026-10-15"))
    }

    @Test func unpaidIsOverdueOnlyAfterTheDueDate() {
        #expect(status(loan(paymentDay: 5)) == LoanMonthStatus.unpaid(dueDate: day("2026-10-05"), isOverdue: true, leftToPay: 50_000))
        #expect(status(loan(paymentDay: 6)) == LoanMonthStatus.unpaid(dueDate: day("2026-10-06"), isOverdue: false, leftToPay: 50_000))
    }

    @Test func paymentLastMonthOnlyIsUnpaid() {
        let result = status(loan(lastPaymentDate: "2026-09-28"), [payment("2026-09-28")])
        #expect(result == unpaidInOctober(leftToPay: 50_000))
    }

    @Test func futureDatedOrOtherLoansPaymentsDoNotCount() {
        let result = status(loan(), [
            payment("2026-10-20"),                  // later this month: not realized yet
            payment("2026-10-03", loanId: "other"), // another loan's payment
        ])
        #expect(result == unpaidInOctober(leftToPay: 50_000))
    }

    @Test func paymentDayIsClampedToEachMonth() {
        let account = loan(termMonths: 24, paymentDay: 31)
        #expect(status(account, today: "2026-11-06") == LoanMonthStatus.unpaid(dueDate: day("2026-11-30"), isOverdue: false, leftToPay: 50_000))
        #expect(status(account, [payment("2026-11-02")], today: "2026-11-06") == LoanMonthStatus.paid(nextDueDate: day("2026-12-31")))
        #expect(status(account, today: "2027-02-03") == LoanMonthStatus.unpaid(dueDate: day("2027-02-28"), isOverdue: false, leftToPay: 50_000))
    }

    @Test func finalMonthAsksForWhatWasOwedWhenItBegan() {
        // 12 000 left on 1 October; 5 000 paid on the 3rd, already taken off the principal.
        // The month still asks for 12 000, so 7 000 is left (not 7 000 - 5 000).
        #expect(status(loan(remaining: 7_000), [payment("2026-10-03", amount: 5_000)]) == unpaidInOctober(leftToPay: 7_000))
        // 12% annuity: 12 000 + 120 interest was due; 5 000 paid (120 interest, 4 880 principal).
        #expect(status(loan(remaining: 7_120, rate: 12), [payment("2026-10-03", amount: 5_000)]) == unpaidInOctober(leftToPay: 7_120))
    }

    // MARK: - Payments in another currency

    @Test func foreignCurrencyPaymentConvertsAtTheRates() {
        let dollars = [payment("2026-10-03", amount: 100, currency: "USD")]
        #expect(status(loan(), dollars, rates: ["USD": 500]) == paidInOctober) // 100 × 500 = 50 000
        // No rate: the unconverted amount, the canonical cold-cache fallback.
        #expect(status(loan(), dollars) == unpaidInOctober(leftToPay: 49_900))
    }

    @Test func foreignCurrencyPaymentUsesTheConversionItWasSavedWith() {
        // The row's own equivalent in the loan's currency, no rates needed.
        let equivalent = [payment("2026-10-03", amount: 100, currency: "USD", targetCurrency: "KZT", targetAmount: 50_000)]
        #expect(status(loan(), equivalent) == paidInOctober)
        // The paying card's leg (convertedAmount, in the card's currency) when the card is in
        // the loan's currency; without knowing the card it is not read as tenge.
        let cardLeg = [payment("2026-10-03", amount: 100, currency: "USD", convertedAmount: 50_000)]
        let card = Account(id: "bank", name: "Card", currency: "KZT")
        #expect(status(loan(), cardLeg, accounts: ["bank": card]) == paidInOctober)
        #expect(status(loan(), cardLeg) == unpaidInOctober(leftToPay: 49_900))
    }

    // MARK: - "Mark as paid" in the schedule

    @Test func markedPaidInTheScheduleIsPaid() {
        // "Mark as paid" writes the schedule row's date to markedPaidThrough, no transaction.
        #expect(status(loan(markedPaidThrough: "2026-10-10")) == paidInOctober)
        // Marked ahead, through a later month: this month is covered too.
        #expect(status(loan(markedPaidThrough: "2027-01-10")) == paidInOctober)
        // Marked through last month only.
        #expect(status(loan(markedPaidThrough: "2026-09-10")) == unpaidInOctober(leftToPay: 50_000))
    }

    @Test func lastPaymentDateAloneIsNotPaid() {
        // What a deleted or a partial payment leaves behind; it used to keep the month "Paid".
        #expect(status(loan(lastPaymentDate: "2026-10-03")) == unpaidInOctober(leftToPay: 50_000))
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
        #expect(status(loan(startDate: "2026-09-20")) == unpaidInOctober(leftToPay: 50_000))
    }

    @Test func loanPastItsLastScheduledMonthHasNoStatus() {
        // 12 payments, October 2025 to September 2026.
        #expect(status(loan(startDate: "2025-09-10")) == nil)
        // 12 payments, November 2025 to October 2026: October is the last one.
        #expect(status(loan(startDate: "2025-10-10")) == unpaidInOctober(leftToPay: 50_000))
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
            let transactions = account.id == "paid" ? [payment("2026-10-01", loanId: "paid", amount: 70_000)] : []
            statuses[account.id] = status(account, transactions)
        }
        #expect(statuses["paid"] == paidInOctober)
        #expect(statuses["closed"] == nil)

        let rates = RateSnapshot(rates: ["USD": 500]) // 1 USD = 500 KZT
        // 100 000 KZT + 200 USD × 500; the paid and the closed loan add nothing.
        #expect(LoanMonthStatusService.unpaidTotal(loans: loans, statuses: statuses, baseCurrency: "KZT", rates: rates) == 200_000)
        #expect(LoanMonthStatusService.unpaidTotal(loans: loans, statuses: statuses, baseCurrency: "USD", rates: rates) == 400)
    }

    @Test func unpaidTotalCountsOnlyWhatIsLeftAfterPartialPayments() {
        let loans = [
            loan(id: "kzt", monthlyPayment: 100_000),
            loan(id: "usd", currency: "USD", remaining: 5_000, monthlyPayment: 200),
            loan(id: "over", monthlyPayment: 70_000),
        ]
        var statuses: [String: LoanMonthStatus] = [:]
        statuses["kzt"] = status(loans[0], [payment("2026-10-02", loanId: "kzt", amount: 30_000)])
        statuses["usd"] = status(loans[1], [payment("2026-10-02", loanId: "usd", amount: 50, currency: "USD")])
        // Paid more than due: counts nothing, never a negative amount.
        statuses["over"] = status(loans[2], [payment("2026-10-01", loanId: "over", amount: 90_000)])
        #expect(statuses["kzt"] == unpaidInOctober(leftToPay: 70_000))
        #expect(statuses["usd"] == unpaidInOctober(leftToPay: 150))

        let rates = RateSnapshot(rates: ["USD": 500])
        // 70 000 KZT + 150 USD × 500.
        #expect(LoanMonthStatusService.unpaidTotal(loans: loans, statuses: statuses, baseCurrency: "KZT", rates: rates) == 145_000)
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
        // From the principal owed when the month began, when given.
        #expect(LoanMonthStatusService.amountDue(lastInstallment, remainingPrincipal: 30_000) == 30_000)
    }
}
