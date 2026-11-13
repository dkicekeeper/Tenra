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

    /// `get_subscription_audit`: every subscription with its real charges
    /// (FinanceToolkitCompute.subscriptionAudit), swept off the main actor.
    func subscriptionAudit() async -> JSONValue {
        let snapshot = makeSnapshot()
        let subscriptions = store.recurringSeries.filter(\.isSubscription).map { series in
            let days: Int = switch series.frequency {
            case .daily: 1
            case .weekly: 7
            case .monthly: 31
            case .quarterly: 92
            case .yearly: 366
            }
            return FinanceToolkitCompute.AuditSubscription(
                id: series.id,
                name: series.description.isEmpty ? series.category : series.description,
                amount: NSDecimalNumber(decimal: series.amount).doubleValue,
                currency: series.currency,
                frequency: series.frequency.rawValue,
                intervalDays: days,
                isActive: series.isActive,
                startDate: series.startDate
            )
        }
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.subscriptionAudit(snapshot, subscriptions: subscriptions)
        }.value
    }

    private struct BalanceInput: Decodable {
        let account: String
        let balance: Double
    }

    /// `draft_balance_correction`: an everyday account set to the balance the bank shows. The
    /// starting balance takes the difference (AccountsViewModel.updateAccount), so no income
    /// or expense is made up.
    func draftBalanceCorrection(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_balance_correction")) }
        let args = try input.decoded(as: BalanceInput.self)
        let reference = args.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = store.accounts.first(where: { $0.id == reference })
            ?? store.accounts.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown account \(reference). Use an account id from <app_context>.")
        }
        guard !account.isLoan, !account.isDeposit else {
            throw FinanceToolError(message: "\(account.name) is a loan or a deposit: its balance follows its terms and is changed on its own screen. Offer an open block to the account.")
        }
        guard args.balance.isFinite else { throw FinanceToolError(message: "balance must be a number.") }
        let current = FinanceToolkitCompute.round2(store.balanceCoordinator.balances[account.id] ?? account.balance)
        let target = FinanceToolkitCompute.round2(args.balance)
        guard abs(target - current) >= 0.01 else {
            throw FinanceToolError(message: "\(account.name) already shows this balance.")
        }
        let id = drafts.add([.balanceCorrection(account: account, from: current, to: target)])
        return .success([
            "draft_id": .string(id),
            "account_id": .string(account.id),
            "account": .string(account.name),
            "currency": .string(account.currency),
            "before": .number(current),
            "after": .number(target),
            "difference": .number(FinanceToolkitCompute.round2(target - current)),
            "saved": false,
        ])
    }

    /// What a balance draft will do (FinanceToolkit.describe).
    func describeBalanceCorrection(_ operation: AgentDraftOperation) -> JSONValue {
        guard case .balanceCorrection(let account, let from, let to) = operation else { return .null }
        return [
            "type": "balance_correction", "account_id": .string(account.id), "account": .string(account.name),
            "currency": .string(account.currency), "before": .number(from), "after": .number(to),
        ]
    }

    /// `suggest_budgets`: the last three whole months per expense category next to its monthly
    /// budget (FinanceToolkitCompute.budgetSuggestions), swept off the main actor.
    func budgetSuggestions() async -> JSONValue {
        let snapshot = makeSnapshot()
        let categories = store.categories.filter { $0.type == .expense }.map { category in
            let amount = category.budgetAmount.flatMap { $0 > 0 ? $0 : nil }
            return FinanceToolkitCompute.BudgetCategory(
                id: category.id,
                name: category.name,
                monthlyLimit: category.budgetPeriod == .monthly ? amount : nil,
                hasOtherPeriod: amount != nil && category.budgetPeriod != .monthly
            )
        }
        let sweepCalendar = calendar
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.budgetSuggestions(snapshot, categories: categories, calendar: sweepCalendar)
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
