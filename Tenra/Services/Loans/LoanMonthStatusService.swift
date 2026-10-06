//
//  LoanMonthStatusService.swift
//  Tenra
//
//  Whether a loan's regular payment for the current calendar month has been made
//  ("Paid this month" / "Not paid" on the loans list and the loan screen), and what the
//  month's unpaid payments add up to in the base currency (loans list summary).
//  Pure: today and the FX table are parameters.
//

import Foundation

/// Where a loan's regular payment for the current calendar month stands.
nonisolated enum LoanMonthStatus: Equatable, Sendable {
    /// A regular payment is recorded this month. `nextDueDate` is next month's payment day.
    case paid(nextDueDate: Date)
    /// No regular payment recorded this month yet. `dueDate` is this month's payment day;
    /// `isOverdue` once that day has passed (due today is not overdue).
    case unpaid(dueDate: Date, isOverdue: Bool)

    /// The date the next regular payment falls due: this month's payment day while it is
    /// unpaid (even once it has passed), next month's once it is paid.
    var nextDueDate: Date {
        switch self {
        case .paid(let nextDueDate): return nextDueDate
        case .unpaid(let dueDate, _): return dueDate
        }
    }
}

nonisolated enum LoanMonthStatusService {

    /// This month's status of `loan`, or nil when it shows none: not a loan, paid off, not
    /// started yet, or past its last scheduled month. As in
    /// `LoanPaymentService.generateAmortizationSchedule`, payment `i` falls `i` months after
    /// `startDate`, so the first one is due the month after the start month and the last one
    /// `termMonths` months after it.
    ///
    /// Paid means a regular payment is recorded in this calendar month:
    /// - a `.loanPayment` to this loan (orientation contract: `targetAccountId` = loan) dated
    ///   from the 1st through today; a future-dated row is not realized yet, or
    /// - the loan's own `lastPaymentDate` on or after the 1st. Every way of recording a payment
    ///   writes it (manual payment, Pay All, linking), and so does "Mark as paid" in the
    ///   amortization schedule, which records a payment made outside the app without a
    ///   transaction.
    ///
    /// An early repayment is neither: it shortens the term or lowers the payment, and the
    /// month's regular payment is still due.
    ///
    /// Dates are read in the Gregorian calendar of the stored "yyyy-MM-dd" keys
    /// (`FastDateParser.calendar`), whatever calendar the device uses.
    ///
    /// - Parameter loanTransactions: the loan's transactions (`transactionsByAccount[loan.id]`).
    ///   Anything other than a regular payment to this loan is ignored.
    static func status(
        loan: Account,
        loanTransactions: [Transaction],
        today: Date
    ) -> LoanMonthStatus? {
        let calendar = FastDateParser.calendar
        guard let info = loan.loanInfo, !info.isPaidOff,
              let start = FastDateParser.date(from: info.startDate),
              let startMonth = startOfMonth(start, calendar: calendar),
              let monthStart = startOfMonth(today, calendar: calendar),
              let elapsedMonths = calendar.dateComponents([.month], from: startMonth, to: monthStart).month,
              elapsedMonths >= 1, elapsedMonths <= info.termMonths,
              let dueDate = paymentDate(day: info.paymentDay, inMonthOf: monthStart, calendar: calendar),
              let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
              let nextDueDate = paymentDate(day: info.paymentDay, inMonthOf: nextMonthStart, calendar: calendar)
        else { return nil }

        // "yyyy-MM-dd" keys compare chronologically as strings.
        let monthStartKey = FastDateParser.string(from: monthStart)
        let todayKey = FastDateParser.string(from: today)
        let paidByTransaction = loanTransactions.contains { tx in
            guard tx.type == .loanPayment, tx.targetAccountId == loan.id else { return false }
            return tx.date >= monthStartKey && tx.date <= todayKey
        }
        let paidBySchedule = info.lastPaymentDate.map { $0 >= monthStartKey } ?? false

        if paidByTransaction || paidBySchedule {
            return .paid(nextDueDate: nextDueDate)
        }
        return .unpaid(dueDate: dueDate, isOverdue: dueDate < calendar.startOfDay(for: today))
    }

    /// One month's regular payment of a loan: `monthlyPayment`, but never more than what is
    /// left to repay (the remaining principal plus the month's interest), so the final month
    /// is not overstated.
    static func amountDue(_ info: LoanInfo) -> Decimal {
        let interest = LoanPaymentService.paymentBreakdown(
            remainingPrincipal: info.remainingPrincipal,
            annualRate: info.interestRateAnnual,
            monthlyPayment: info.monthlyPayment
        ).interest
        return min(info.monthlyPayment, info.remainingPrincipal + interest)
    }

    /// Sum in `baseCurrency` of `amountDue` over the loans whose status is `.unpaid`.
    ///
    /// Each loan converts from its own currency through `rates`, which has the semantics of
    /// `CurrencyConverter.convertSync`. A missing rate falls back to the unconverted amount,
    /// the canonical cold-cache fallback; the caller re-reads once rates land
    /// (`currencyRatesVersion`).
    static func unpaidTotal(
        loans: [Account],
        statuses: [String: LoanMonthStatus],
        baseCurrency: String,
        rates: RateSnapshot
    ) -> Double {
        var total = 0.0
        for loan in loans {
            guard let status = statuses[loan.id], case .unpaid = status,
                  let info = loan.loanInfo else { continue }
            let amount = NSDecimalNumber(decimal: amountDue(info)).doubleValue
            total += rates.convert(amount, from: loan.currency, to: baseCurrency) ?? amount
        }
        return total
    }

    /// The loans summary's "Total Debt" and "Monthly": remaining principal and monthly
    /// payment summed over `loans`. In the loans' own currency when they share one
    /// (nothing to convert), else in `baseCurrency`, each loan converted first through
    /// `rates` (unconverted on a missing rate, as in `unpaidTotal`). Summed raw, a 5 000 USD
    /// loan and a 500 000 ₸ loan showed 505 000 in the first loan's currency.
    /// `currency` is nil when there are no loans.
    static func summaryTotals(
        loans: [Account],
        baseCurrency: String,
        rates: RateSnapshot
    ) -> (currency: String?, debt: Double, monthly: Double) {
        let currencies = Set(loans.map(\.currency))
        guard let currency = currencies.count > 1 ? baseCurrency : currencies.first else {
            return (nil, 0, 0)
        }
        var debt = 0.0
        var monthly = 0.0
        for loan in loans {
            guard let info = loan.loanInfo else { continue }
            let principal = NSDecimalNumber(decimal: info.remainingPrincipal).doubleValue
            let payment = NSDecimalNumber(decimal: info.monthlyPayment).doubleValue
            debt += rates.convert(principal, from: loan.currency, to: currency) ?? principal
            monthly += rates.convert(payment, from: loan.currency, to: currency) ?? payment
        }
        return (currency, debt, monthly)
    }

    // MARK: - Calendar helpers

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    /// The payment day clamped to the month's length (day 31 → Feb 28 → Mar 31), like
    /// `LoanPaymentService.nextPaymentDate`.
    private static func paymentDate(day: Int, inMonthOf monthStart: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: monthStart)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        components.day = min(max(day, 1), daysInMonth)
        return calendar.date(from: components)
    }
}
