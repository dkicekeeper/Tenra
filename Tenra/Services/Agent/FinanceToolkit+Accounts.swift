//
//  FinanceToolkit+Accounts.swift
//  Tenra
//
//  The terms of the person's loans and deposits for the assistant (docs/plan-ten-agent.md
//  stage 2, docs/domains/assistant.md §3): `get_loans` (what is left, the rate, the monthly
//  payment and its day, the term, payments made, interest paid) and `get_deposits` (the
//  balance, the rate, whether interest is added to the deposit, the posting day, interest
//  accrued since the last posting). Read only: a loan's or a deposit's state is written by its
//  own services (CLAUDE.md red flags 2 and 8).
//

import Foundation

extension FinanceToolkit {
    private static func number(_ value: Decimal) -> JSONValue {
        .number(FinanceToolkitCompute.round2(NSDecimalNumber(decimal: value).doubleValue))
    }

    /// `get_loans`: every loan account with its terms.
    func loansResult() -> JSONValue {
        let loans: [JSONValue] = store.accounts.compactMap { account in
            guard let loan = account.loanInfo else { return nil }
            return [
                "id": .string(account.id),
                "name": .string(account.name),
                "bank": .string(loan.bankName),
                "currency": .string(account.currency),
                "remaining": Self.number(loan.remainingPrincipal),
                "original": Self.number(loan.originalPrincipal),
                "rate_percent": Self.number(loan.interestRateAnnual),
                "monthly_payment": Self.number(loan.monthlyPayment),
                "payment_day": .number(Double(loan.paymentDay)),
                "term_months": .number(Double(loan.termMonths)),
                "payments_made": .number(Double(loan.paymentsMade)),
                "payments_left": .number(Double(max(loan.termMonths - loan.paymentsMade, 0))),
                "start_date": .string(loan.startDate),
                "end_date": .string(loan.endDate),
                "last_payment_date": loan.lastPaymentDate.map(JSONValue.string) ?? .null,
                "interest_paid": Self.number(loan.totalInterestPaid),
            ]
        }
        return ["loans": .array(loans)]
    }

    /// `find_recurring_candidates`: expenses that repeat like a subscription and are not one
    /// yet (FinanceToolkitCompute.recurringCandidates), swept off the main actor.
    func recurringCandidates() async -> JSONValue {
        let snapshot = makeSnapshot()
        let known = Set(store.recurringSeries.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.recurringCandidates(snapshot, knownNames: known)
        }.value
    }

    /// `find_duplicates`: incomes and expenses that look recorded twice
    /// (FinanceToolkitCompute.duplicates), swept off the main actor.
    func duplicates() async -> JSONValue {
        let snapshot = makeSnapshot()
        let sweepCalendar = calendar
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.duplicates(snapshot, calendar: sweepCalendar)
        }.value
    }

    /// `get_deposits`: every deposit account with its terms and its balance.
    func depositsResult() -> JSONValue {
        let balances = store.balanceCoordinator.balances
        let deposits: [JSONValue] = store.accounts.compactMap { account in
            guard let deposit = account.depositInfo else { return nil }
            return [
                "id": .string(account.id),
                "name": .string(account.name),
                "bank": .string(deposit.bankName),
                "currency": .string(account.currency),
                "balance": .number(FinanceToolkitCompute.round2(balances[account.id] ?? account.balance)),
                "rate_percent": Self.number(deposit.interestRateAnnual),
                "capitalization": .bool(deposit.capitalizationEnabled),
                "interest_posting_day": .number(Double(deposit.interestPostingDay)),
                "accrued_interest": Self.number(deposit.interestAccruedForCurrentPeriod),
                "start_date": .string(deposit.startDate),
            ]
        }
        return ["deposits": .array(deposits)]
    }
}
