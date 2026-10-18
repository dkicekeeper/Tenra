//
//  LoanWhatIf.swift
//  Tenra
//
//  What a loan costs from today, and what it would cost refinanced, with an extra payment every
//  month or with an early repayment now. Pure arithmetic on the remaining principal, the rate
//  and the payment, for the assistant's `simulate_loan` (docs/plan-ai-assistant.md §3.1); the
//  same formulas run in server/assistant/eval/simulator.ts, keep them in step.
//

import Foundation

nonisolated enum LoanWhatIf {
    struct Plan: Equatable {
        let principal: Double
        let ratePercent: Double
        let monthlyPayment: Double
        let monthsLeft: Int
        let totalInterest: Double
    }

    struct Scenario: Equatable {
        /// Annual rate after refinancing; nil keeps the current one.
        var newRatePercent: Double?
        /// Term after refinancing, in months; nil keeps the months left.
        var newMonths: Int?
        /// One-off cost of refinancing, paid up front.
        var fees: Double = 0
        /// Paid on top of the monthly payment, every month.
        var extraMonthly: Double = 0
        /// Early repayment now.
        var oneOff: Double = 0
        /// The early repayment lowers the payment and keeps the term, instead of the reverse.
        var oneOffReducesPayment = false

        var isEmpty: Bool {
            newRatePercent == nil && newMonths == nil && fees == 0 && extraMonthly == 0 && oneOff == 0
        }

        var refinances: Bool { newRatePercent != nil || newMonths != nil }
    }

    enum Failure: Error, Equatable {
        /// The payment does not even cover the month's interest.
        case paymentBelowInterest
        case oneOffCoversLoan
    }

    /// Months until the loan is repaid with this payment, and the interest paid on the way.
    /// The last payment is only what is left.
    static func repay(principal: Double, ratePercent: Double, payment: Double) -> (months: Int, interest: Double)? {
        guard principal > 0.005 else { return (0, 0) }
        guard payment > 0 else { return nil }
        let rate = ratePercent / 100 / 12
        var left = principal, interest = 0.0, months = 0
        while left > 0.005 && months < 1200 {
            let monthInterest = left * rate
            guard payment > monthInterest else { return nil }
            interest += monthInterest
            left -= min(payment, left + monthInterest) - monthInterest
            months += 1
        }
        return (months, interest)
    }

    /// The annuity payment that repays `principal` in `months`.
    static func annuity(principal: Double, ratePercent: Double, months: Int) -> Double {
        guard months > 0 else { return principal }
        let rate = ratePercent / 100 / 12
        guard rate > 0 else { return principal / Double(months) }
        let power = pow(1 + rate, Double(months))
        return principal * rate * power / (power - 1)
    }

    /// The loan as it runs now: the payment it has, or the annuity over `monthsLeft` when it has
    /// none.
    static func plan(principal: Double, ratePercent: Double, payment: Double?, monthsLeft: Int?) throws -> Plan {
        let monthly = payment.flatMap { $0 > 0 ? $0 : nil }
            ?? annuity(principal: principal, ratePercent: ratePercent, months: monthsLeft ?? 0)
        guard let run = repay(principal: principal, ratePercent: ratePercent, payment: monthly) else {
            throw Failure.paymentBelowInterest
        }
        return Plan(principal: principal, ratePercent: ratePercent, monthlyPayment: monthly, monthsLeft: run.months, totalInterest: run.interest)
    }

    /// The loan after the scenario. Refinancing (or an early repayment that lowers the payment)
    /// sets a new annuity over the new term; otherwise the payment stays and the term shrinks.
    /// The extra monthly amount goes on top in both cases.
    static func apply(_ scenario: Scenario, to current: Plan) throws -> Plan {
        let principal = current.principal - scenario.oneOff
        guard principal > 0.005 else { throw Failure.oneOffCoversLoan }
        let rate = scenario.newRatePercent ?? current.ratePercent
        let base: Double
        if scenario.refinances || (scenario.oneOff > 0 && scenario.oneOffReducesPayment) {
            base = annuity(principal: principal, ratePercent: rate, months: scenario.newMonths ?? current.monthsLeft)
        } else {
            base = current.monthlyPayment
        }
        let payment = base + scenario.extraMonthly
        guard let run = repay(principal: principal, ratePercent: rate, payment: payment) else {
            throw Failure.paymentBelowInterest
        }
        return Plan(principal: principal, ratePercent: rate, monthlyPayment: payment, monthsLeft: run.months, totalInterest: run.interest)
    }

    /// Months of the lower payment it takes to earn back the fees; nil without fees or without
    /// a lower payment.
    static func breakEvenMonths(fees: Double, current: Plan, scenario: Plan) -> Int? {
        let saving = current.monthlyPayment - scenario.monthlyPayment
        guard fees > 0, saving > 0.005 else { return nil }
        // The fees come from the model: absurd ones must not overflow Int (a trap).
        return Int(exactly: (fees / saving).rounded(.up))
    }
}
