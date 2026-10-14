//
//  FinanceToolkit+Plans.swift
//  Tenra
//
//  Ten's tools for savings goals and personal debts (docs/domains/goals-and-debts.md,
//  docs/plan-ai-assistant.md phase 4). `get_goals` and `get_debts` read them with the app's
//  own progress (GoalProgress, PersonalDebt); `draft_goal`, `draft_goal_contribution`,
//  `draft_debt` and `draft_debt_repayment` file drafts the person saves on the confirm card,
//  through GoalStore and DebtStore. New debts are Tenra Pro: without it `draft_debt` says so
//  and points to remembering it as a fact instead. Input shapes are the contract in
//  server/assistant/src/tools.ts.
//

import Foundation

extension FinanceToolkit {
    // MARK: - Read

    /// `get_goals`: every goal with what is saved, what is left, the deadline and what to put
    /// aside each month, and everything saved in the base currency.
    func goalsResult() async throws -> AgentToolOutput {
        guard let goals else { return .failure(Self.notYet("get_goals")) }
        await goals.load()
        let today = now()
        let items: [JSONValue] = goals.goals.map { goal in
            let status = GoalProgress.status(
                target: goal.targetAmount,
                saved: goals.saved(for: goal),
                deadline: goal.deadline,
                today: today,
                calendar: calendar
            )
            let account = goals.followsAccount(goal) ? store.accounts.first(where: { $0.id == goal.linkedAccountId }) : nil
            return [
                "id": .string(goal.id),
                "name": .string(goal.name),
                "currency": .string(goal.currency),
                "target": .number(FinanceToolkitCompute.round2(goal.targetAmount)),
                "saved": .number(FinanceToolkitCompute.round2(status.saved)),
                "left": .number(FinanceToolkitCompute.round2(status.left)),
                "percent": .number((status.fraction * 100).rounded()),
                "reached": .bool(status.isReached),
                "deadline": goal.deadline.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "months_left": status.monthsLeft.map { JSONValue.number(Double($0)) } ?? .null,
                "monthly": status.monthly.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
                "overdue": .bool(status.isOverdue),
                "account_id": account.map { JSONValue.string($0.id) } ?? .null,
                "account": account.map { JSONValue.string($0.name) } ?? .null,
            ]
        }
        return .success([
            "goals": .array(items),
            "total_saved": .number(FinanceToolkitCompute.round2(goals.totalSaved(in: store.baseCurrency))),
            "currency": .string(store.baseCurrency),
        ])
    }

    /// `get_debts`: open debts both ways (the soonest due first) and the latest settled ones,
    /// with what came back and what is left, and the open totals in the base currency.
    func debtsResult() async throws -> AgentToolOutput {
        guard let debts else { return .failure(Self.notYet("get_debts")) }
        await debts.load()
        let today = now()
        let base = store.baseCurrency
        let listed = debts.open(.owedToMe) + debts.open(.iOwe) + debts.settled.prefix(Self.settledDebtsListed)
        let items: [JSONValue] = listed.map { debt in
            [
                "id": .string(debt.id),
                "direction": .string(Self.wire(debt.direction)),
                "person": .string(debt.person),
                "currency": .string(debt.currency),
                "amount": .number(FinanceToolkitCompute.round2(debt.amount)),
                "repaid": .number(FinanceToolkitCompute.round2(debt.repaid)),
                "remaining": .number(FinanceToolkitCompute.round2(debt.remaining)),
                "date": .string(FastDateParser.string(from: debt.date)),
                "due_date": debt.dueDate.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "overdue": .bool(debt.isOverdue(today: today, calendar: calendar)),
                "settled": .bool(debt.isSettled),
                "settled_on": debt.settledAt.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "note": debt.note.map(JSONValue.string) ?? .null,
            ]
        }
        return .success([
            "debts": .array(items),
            "owed_to_me": .number(FinanceToolkitCompute.round2(debts.total(.owedToMe, in: base))),
            "i_owe": .number(FinanceToolkitCompute.round2(debts.total(.iOwe, in: base))),
            "currency": .string(base),
        ])
    }

    /// Settled debts listed by `get_debts`, the latest first.
    static let settledDebtsListed = 10

    // MARK: - Draft a goal

    private struct DraftGoalInput: Decodable {
        let name: String
        let target: Double
        let currency: String?
        let deadline: String?
        let account: String?
        let alreadySaved: Double?

        enum CodingKeys: String, CodingKey {
            case name, target, currency, deadline, account
            case alreadySaved = "already_saved"
        }
    }

    /// `draft_goal`: a new savings goal. With an account it follows that account's balance;
    /// without one it starts from `already_saved` and grows with contributions.
    func draftGoal(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let goals else { return .failure(Self.notYet("draft_goal")) }
        let args = try input.decoded(as: DraftGoalInput.self)
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceToolError(message: "name is required.") }
        guard args.target.isFinite, args.target > 0 else { throw FinanceToolError(message: "target must be positive.") }

        let today = calendar.startOfDay(for: now())
        var deadline: Date?
        if let raw = args.deadline, !raw.isEmpty {
            guard let date = FastDateParser.date(from: raw) else { throw FinanceToolError(message: "deadline must be YYYY-MM-DD.") }
            guard date >= today else { throw FinanceToolError(message: "deadline cannot be in the past.") }
            guard let limit = calendar.date(byAdding: .year, value: 50, to: today), date <= limit else {
                throw FinanceToolError(message: "deadline must be within 50 years.")
            }
            deadline = date
        }

        var account: Account?
        if let reference = args.account, !reference.isEmpty {
            guard let named = resolveAccount(reference, in: store.accounts.filter { !$0.isLoan }) else {
                throw FinanceToolError(message: "Unknown account \(reference). Use an account id from <app_context> (not a loan).")
            }
            account = named
        }
        let alreadySaved = args.alreadySaved ?? 0
        guard alreadySaved.isFinite, alreadySaved >= 0 else { throw FinanceToolError(message: "already_saved cannot be negative.") }
        if account != nil, alreadySaved > 0 {
            throw FinanceToolError(message: "already_saved is for a goal without an account: a goal with an account follows its balance.")
        }

        let currency = args.currency.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? account?.currency
            ?? store.baseCurrency
        let goal = SavingsGoal(
            name: name,
            targetAmount: FinanceToolkitCompute.round2(args.target),
            currency: currency,
            deadline: deadline,
            linkedAccountId: account?.id,
            contributions: alreadySaved > 0
                ? [GoalContribution(amount: FinanceToolkitCompute.round2(alreadySaved), date: now())]
                : [],
            createdAt: now()
        )
        let status = GoalProgress.status(target: goal.targetAmount, saved: goals.saved(for: goal), deadline: deadline, today: today, calendar: calendar)
        let id = drafts.add([.goal(goal)])
        return .success([
            "draft_id": .string(id),
            "name": .string(name),
            "target": .number(goal.targetAmount),
            "currency": .string(currency),
            "deadline": deadline.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
            "account_id": account.map { JSONValue.string($0.id) } ?? .null,
            "account": account.map { JSONValue.string($0.name) } ?? .null,
            "saved_amount": .number(FinanceToolkitCompute.round2(status.saved)),
            "left": .number(FinanceToolkitCompute.round2(status.left)),
            "months_left": status.monthsLeft.map { JSONValue.number(Double($0)) } ?? .null,
            "monthly": status.monthly.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
            "saved": false,
        ])
    }

    // MARK: - Draft money towards a goal

    private struct DraftContributionInput: Decodable {
        let goal: String
        let amount: Double
        let date: String?
        let note: String?
    }

    /// `draft_goal_contribution`: money put towards a goal without an account, in the goal's
    /// currency. A goal that follows an account grows with that account: the answer says to
    /// draft a transfer instead.
    func draftGoalContribution(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let goals else { return .failure(Self.notYet("draft_goal_contribution")) }
        await goals.load()
        let args = try input.decoded(as: DraftContributionInput.self)
        let reference = args.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let goal = goals.goal(id: reference) ?? goals.goals.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown goal \(reference). Use a goal id from <app_context>.")
        }
        if goals.followsAccount(goal) {
            let account = store.accounts.first { $0.id == goal.linkedAccountId }?.name ?? ""
            throw FinanceToolError(message: "The goal \(goal.name) follows the balance of the account \(account). Money towards it is a transfer to that account: use draft_transactions with type transfer.")
        }
        guard args.amount.isFinite, args.amount > 0 else { throw FinanceToolError(message: "amount must be positive.") }
        let date = try pastOrToday(args.date, field: "date")
        let note = args.note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let contribution = GoalContribution(amount: FinanceToolkitCompute.round2(args.amount), date: date, note: note)

        let savedAfter = goals.saved(for: goal) + contribution.amount
        let after = GoalProgress.status(target: goal.targetAmount, saved: savedAfter, deadline: goal.deadline, today: now(), calendar: calendar)
        let id = drafts.add([.goalContribution(goalId: goal.id, contribution)])
        return .success([
            "draft_id": .string(id),
            "goal_id": .string(goal.id),
            "goal": .string(goal.name),
            "amount": .number(contribution.amount),
            "currency": .string(goal.currency),
            "date": .string(FastDateParser.string(from: date)),
            "saved_amount_after": .number(FinanceToolkitCompute.round2(after.saved)),
            "left_after": .number(FinanceToolkitCompute.round2(after.left)),
            "reaches_target": .bool(after.isReached),
            "saved": false,
        ])
    }

    // MARK: - Draft a debt

    private struct DraftDebtInput: Decodable {
        let direction: String
        let person: String
        let amount: Double
        let currency: String?
        let date: String?
        let dueDate: String?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case direction, person, amount, currency, date, note
            case dueDate = "due_date"
        }
    }

    /// `draft_debt`: money lent to someone (`owed_to_me`) or borrowed from someone (`i_owe`).
    /// Tenra Pro: without it the answer says so and points to remembering it as a fact.
    func draftDebt(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, debts != nil else { return .failure(Self.notYet("draft_debt")) }
        guard isPro() else {
            throw FinanceToolError(message: "Personal debts are a Tenra Pro feature and this user does not have Tenra Pro. Say so in one sentence (they can turn Pro on in the app), and offer to remember the debt as a fact with draft_fact instead.")
        }
        let args = try input.decoded(as: DraftDebtInput.self)
        guard let direction = Self.direction(args.direction) else {
            throw FinanceToolError(message: "direction must be owed_to_me or i_owe.")
        }
        let person = args.person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !person.isEmpty else { throw FinanceToolError(message: "person is required.") }
        guard args.amount.isFinite, args.amount > 0 else { throw FinanceToolError(message: "amount must be positive.") }
        let date = try pastOrToday(args.date, field: "date")
        var dueDate: Date?
        if let raw = args.dueDate, !raw.isEmpty {
            guard let due = FastDateParser.date(from: raw) else { throw FinanceToolError(message: "due_date must be YYYY-MM-DD.") }
            guard due >= calendar.startOfDay(for: date) else { throw FinanceToolError(message: "due_date cannot be before date.") }
            dueDate = due
        }
        let currency = args.currency.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? store.baseCurrency
        let note = args.note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let debt = PersonalDebt(
            direction: direction,
            person: person,
            amount: FinanceToolkitCompute.round2(args.amount),
            currency: currency,
            date: date,
            dueDate: dueDate,
            note: note
        )
        let id = drafts.add([.debt(debt)])
        return .success([
            "draft_id": .string(id),
            "direction": .string(Self.wire(direction)),
            "person": .string(person),
            "amount": .number(debt.amount),
            "currency": .string(currency),
            "date": .string(FastDateParser.string(from: date)),
            "due_date": dueDate.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
            "note": note.map(JSONValue.string) ?? .null,
            "saved": false,
        ])
    }

    // MARK: - Draft money back on a debt

    private struct DraftRepaymentInput: Decodable {
        let debt: String
        let amount: Double?
        let date: String?
        let note: String?
    }

    /// `draft_debt_repayment`: money back on an open debt, in its currency; no amount is all
    /// that is left. A repayment that covers the rest settles the debt on Save.
    func draftDebtRepayment(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let debts else { return .failure(Self.notYet("draft_debt_repayment")) }
        await debts.load()
        let args = try input.decoded(as: DraftRepaymentInput.self)
        let reference = args.debt.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = debts.debts.filter { !$0.isSettled }
        let debt: PersonalDebt
        if let byId = open.first(where: { $0.id == reference }) {
            debt = byId
        } else {
            let named = open.filter { $0.person.lowercased() == reference.lowercased() }
            guard let first = named.first else {
                throw FinanceToolError(message: "No open debt \(reference). Use a debt id from <app_context>.")
            }
            guard named.count == 1 else {
                throw FinanceToolError(message: "\(reference) has several open debts (\(named.map(\.id).joined(separator: ", "))). Use the debt id.")
            }
            debt = first
        }
        let amount = FinanceToolkitCompute.round2(args.amount ?? debt.remaining)
        guard amount.isFinite, amount > 0 else { throw FinanceToolError(message: "amount must be positive.") }
        guard amount <= debt.remaining + 0.005 else {
            throw FinanceToolError(message: "That is more than what is left on this debt (\(FinanceToolkitCompute.round2(debt.remaining)) \(debt.currency)).")
        }
        let date = try pastOrToday(args.date, field: "date")
        let note = args.note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let repayment = DebtRepayment(amount: amount, date: date, note: note)
        let remainingAfter = max(0, debt.remaining - amount)
        let id = drafts.add([.debtRepayment(debtId: debt.id, repayment)])
        return .success([
            "draft_id": .string(id),
            "debt_id": .string(debt.id),
            "person": .string(debt.person),
            "direction": .string(Self.wire(debt.direction)),
            "amount": .number(amount),
            "currency": .string(debt.currency),
            "date": .string(FastDateParser.string(from: date)),
            "remaining_after": .number(FinanceToolkitCompute.round2(remainingAfter)),
            "settles": .bool(remainingAfter < 0.005),
            "saved": false,
        ])
    }

    // MARK: - Describe

    /// What a goal or debt draft will write (FinanceToolkit.describe).
    func describePlan(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .goal(let goal):
            return [
                "type": "goal",
                "name": .string(goal.name),
                "target": .number(goal.targetAmount),
                "currency": .string(goal.currency),
                "deadline": goal.deadline.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "account_id": goal.linkedAccountId.map(JSONValue.string) ?? .null,
                "already_saved": .number(goal.contributed),
            ]
        case .goalContribution(let goalId, let contribution):
            return [
                "type": "goal_contribution",
                "goal_id": .string(goalId),
                "goal": goals?.goal(id: goalId).map { JSONValue.string($0.name) } ?? .null,
                "amount": .number(contribution.amount),
                "date": .string(FastDateParser.string(from: contribution.date)),
                "note": contribution.note.map(JSONValue.string) ?? .null,
            ]
        case .debt(let debt):
            return [
                "type": "debt",
                "direction": .string(Self.wire(debt.direction)),
                "person": .string(debt.person),
                "amount": .number(debt.amount),
                "currency": .string(debt.currency),
                "date": .string(FastDateParser.string(from: debt.date)),
                "due_date": debt.dueDate.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "note": debt.note.map(JSONValue.string) ?? .null,
            ]
        case .debtRepayment(let debtId, let repayment):
            return [
                "type": "debt_repayment",
                "debt_id": .string(debtId),
                "person": debts?.debt(id: debtId).map { JSONValue.string($0.person) } ?? .null,
                "amount": .number(repayment.amount),
                "date": .string(FastDateParser.string(from: repayment.date)),
                "note": repayment.note.map(JSONValue.string) ?? .null,
            ]
        default:
            return .null
        }
    }

    // MARK: - Helpers

    /// The direction as the tools name it.
    static func wire(_ direction: DebtDirection) -> String {
        direction == .owedToMe ? "owed_to_me" : "i_owe"
    }

    static func direction(_ wire: String) -> DebtDirection? {
        switch wire {
        case "owed_to_me": .owedToMe
        case "i_owe": .iOwe
        default: nil
        }
    }

    /// A date the model gave, today or earlier; none is now.
    private func pastOrToday(_ raw: String?, field: String) throws -> Date {
        guard let raw, !raw.isEmpty else { return now() }
        guard let date = FastDateParser.date(from: raw) else { throw FinanceToolError(message: "\(field) must be YYYY-MM-DD.") }
        guard date <= now() else { throw FinanceToolError(message: "\(field) cannot be in the future.") }
        return date
    }
}
