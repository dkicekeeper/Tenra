//
//  LoanMonthStatusService.swift
//  Tenra
//
//  Whether a loan's payment for the current calendar month has been made ("Paid this
//  month" / "Not paid" on the loans list and the loan screen), and what is still to pay
//  this month in the base currency (loans list summary). Paid means this month's payments
//  to the loan add up to the month's amount due.
//  Pure: today and the FX table are parameters.
//

import Foundation

/// Where a loan's payment for the current calendar month stands.
nonisolated enum LoanMonthStatus: Equatable, Sendable {
    /// This month's payments cover the month's amount due, or "Mark as paid" in the
    /// schedule covered the month. `nextDueDate` is next month's payment day.
    case paid(nextDueDate: Date)
    /// This month's payments fall short of the amount due (none, or partial ones).
    /// `dueDate` is this month's payment day; `isOverdue` once that day has passed (due
    /// today is not overdue). `leftToPay` is the amount due minus this month's payments,
    /// in the loan's currency.
    case unpaid(dueDate: Date, isOverdue: Bool, leftToPay: Double)

    /// The date the next payment falls due: this month's payment day while it is unpaid
    /// (even once it has passed), next month's once it is paid.
    var nextDueDate: Date {
        switch self {
        case .paid(let nextDueDate): return nextDueDate
        case .unpaid(let dueDate, _, _): return dueDate
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
    /// Paid means this month's payments add up to at least the month's amount due
    /// (`amountDue`): every `.loanPayment` and `.loanEarlyRepayment` to this loan
    /// (orientation contract: `targetAccountId` = loan) dated from the 1st through today, in
    /// the loan's currency (`LoanPaymentService.recordedPayment`; a payment in another
    /// currency converts through the conversion it was saved with, else at `rates`). A
    /// future-dated row is not realized yet. Partial payments leave the month unpaid with
    /// the rest in `leftToPay`.
    ///
    /// "Mark as paid" in the amortization schedule (a payment made outside the app,
    /// recorded without a transaction) also makes the month paid: `markedPaidThrough` on or
    /// after the 1st. `lastPaymentDate` plays no part: a partial or a deleted payment leaves
    /// it behind.
    ///
    /// Dates are read in the Gregorian calendar of the stored "yyyy-MM-dd" keys
    /// (`FastDateParser.calendar`), whatever calendar the device uses.
    ///
    /// - Parameters:
    ///   - loanTransactions: the loan's transactions (`transactionsByAccount[loan.id]`).
    ///     Anything other than a payment to this loan is ignored.
    ///   - accountsById: the accounts, for the currency of a paying account whose leg a
    ///     payment in another currency was converted into.
    static func status(
        loan: Account,
        loanTransactions: [Transaction],
        today: Date,
        rates: RateSnapshot,
        accountsById: [String: Account] = [:]
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

        if let marked = info.markedPaidThrough, marked >= monthStartKey {
            return .paid(nextDueDate: nextDueDate)
        }

        // Every payment to this loan from the 1st on, in the loan's currency.
        let sinceMonthStart: [LoanPaymentService.RecordedPayment] = loanTransactions.compactMap { tx in
            guard tx.type == .loanPayment || tx.type == .loanEarlyRepayment,
                  tx.targetAccountId == loan.id,
                  tx.date >= monthStartKey else { return nil }
            return LoanPaymentService.recordedPayment(
                tx,
                loanCurrency: loan.currency,
                sourceCurrency: tx.accountId.flatMap { accountsById[$0]?.currency },
                rates: rates
            )
        }
        let paid = sinceMonthStart
            .filter { $0.date <= todayKey }
            .reduce(Decimal(0)) { $0 + $1.amount }

        // The month asks for its payment capped at what was owed when it began: the
        // payments already in `remainingPrincipal` are undone, so paying off the last
        // 12 000 in two halves still asks for 12 000, not for the 6 000 left after the first.
        let owedAtMonthStart = LoanPaymentService.remainingBefore(
            sinceMonthStart,
            remainingAfter: info.remainingPrincipal,
            annualRate: info.interestRateAnnual
        )
        let leftToPay = max(0, amountDue(info, remainingPrincipal: owedAtMonthStart) - paid)

        if leftToPay <= LoanInfo.paidOffThreshold {
            return .paid(nextDueDate: nextDueDate)
        }
        return .unpaid(
            dueDate: dueDate,
            isOverdue: dueDate < calendar.startOfDay(for: today),
            leftToPay: NSDecimalNumber(decimal: leftToPay).doubleValue
        )
    }

    /// One month's payment of a loan: `monthlyPayment`, but never more than what is left to
    /// repay (the principal owed plus the month's interest), so the final month is not
    /// overstated.
    ///
    /// - Parameter remainingPrincipal: the principal owed when the month began; the loan's
    ///   current remaining principal by default.
    static func amountDue(_ info: LoanInfo, remainingPrincipal: Decimal? = nil) -> Decimal {
        let owed = remainingPrincipal ?? info.remainingPrincipal
        let interest = LoanPaymentService.paymentBreakdown(
            remainingPrincipal: owed,
            annualRate: info.interestRateAnnual,
            monthlyPayment: info.monthlyPayment
        ).interest
        return min(info.monthlyPayment, owed + interest)
    }

    /// Sum in `baseCurrency` of what is still to pay this month (`leftToPay`: the amount due
    /// minus this month's payments) over the loans whose status is `.unpaid`.
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
            guard case .unpaid(_, _, let leftToPay)? = statuses[loan.id] else { continue }
            total += rates.convert(leftToPay, from: loan.currency, to: baseCurrency) ?? leftToPay
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
