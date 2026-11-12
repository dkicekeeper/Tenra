//
//  FinanceToolkit+PlanChanges.swift
//  Tenra
//
//  The assistant changes a savings goal or a personal debt that is already kept
//  (docs/plan-ten-agent.md stage 2): `draft_goal_change` (a new name, target or deadline) and
//  `draft_debt_change` (a new due date or note, or marking the debt settled), both as drafts
//  whose card shows what is there and what it becomes. Save goes through `GoalStore.update` and
//  `DebtStore.update`; Undo puts the previous goal or debt back.
//

import Foundation

extension FinanceToolkit {
    private struct GoalChangeInput: Decodable {
        let goal: String
        let name: String?
        let target: Double?
        let deadline: String?
    }

    private struct DebtChangeInput: Decodable {
        let debt: String
        let dueDate: String?
        let settle: Bool?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case debt, settle, note
            case dueDate = "due_date"
        }
    }

    /// A day today or later, within fifty years.
    private func futureDay(_ raw: String, field: String) throws -> Date {
        let today = calendar.startOfDay(for: now())
        guard let date = FastDateParser.date(from: raw) else { throw FinanceToolError(message: "\(field) must be YYYY-MM-DD.") }
        guard date >= today else { throw FinanceToolError(message: "\(field) cannot be in the past.") }
        guard let limit = calendar.date(byAdding: .year, value: 50, to: today), date <= limit else {
            throw FinanceToolError(message: "\(field) must be within 50 years.")
        }
        return date
    }

    private static func day(_ date: Date?) -> JSONValue {
        date.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null
    }

    /// `draft_goal_change`: a goal with a new name, target or deadline.
    func draftGoalChange(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let goals else { return .failure(Self.notYet("draft_goal_change")) }
        await goals.load()
        let args = try input.decoded(as: GoalChangeInput.self)
        let reference = args.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let before = goals.goal(id: reference) ?? goals.goals.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown goal \(reference). Use a goal id from <app_context>.")
        }
        var after = before
        if let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { after.name = name }
        if let target = args.target {
            guard target.isFinite, target > 0 else { throw FinanceToolError(message: "target must be positive.") }
            after.targetAmount = FinanceToolkitCompute.round2(target)
        }
        if let raw = args.deadline, !raw.isEmpty { after.deadline = try futureDay(raw, field: "deadline") }
        guard after != before else {
            throw FinanceToolError(message: "Nothing changes: give a new name, target or deadline.")
        }
        let status = GoalProgress.status(
            target: after.targetAmount,
            saved: goals.saved(for: before),
            deadline: after.deadline,
            today: now(),
            calendar: calendar
        )
        let id = drafts.add([.goalChange(before: before, after: after)])
        return .success([
            "draft_id": .string(id),
            "goal_id": .string(before.id),
            "currency": .string(before.currency),
            "before": Self.summary(of: before),
            "after": Self.summary(of: after),
            "left": .number(FinanceToolkitCompute.round2(status.left)),
            "monthly": status.monthly.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
            "saved": false,
        ])
    }

    /// `draft_debt_change`: an open debt with a new due date or note, or marked settled (it was
    /// returned outside the app, or the rest is forgiven).
    func draftDebtChange(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let debts else { return .failure(Self.notYet("draft_debt_change")) }
        await debts.load()
        let args = try input.decoded(as: DebtChangeInput.self)
        let reference = args.debt.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = debts.debts.filter { !$0.isSettled }
        let before: PersonalDebt
        if let byId = open.first(where: { $0.id == reference }) {
            before = byId
        } else {
            let named = open.filter { $0.person.lowercased() == reference.lowercased() }
            guard let first = named.first else {
                throw FinanceToolError(message: "No open debt \(reference). Use a debt id from <app_context>.")
            }
            guard named.count == 1 else {
                throw FinanceToolError(message: "\(reference) has several open debts (\(named.map(\.id).joined(separator: ", "))). Use the debt id.")
            }
            before = first
        }
        var after = before
        if let raw = args.dueDate, !raw.isEmpty { after.dueDate = try futureDay(raw, field: "due_date") }
        if let note = args.note?.trimmingCharacters(in: .whitespacesAndNewlines) { after.note = note.isEmpty ? nil : note }
        if args.settle == true { after.settledAt = now() }
        guard after != before else {
            throw FinanceToolError(message: "Nothing changes: give a new due_date or note, or settle true.")
        }
        let id = drafts.add([.debtChange(before: before, after: after)])
        return .success([
            "draft_id": .string(id),
            "debt_id": .string(before.id),
            "person": .string(before.person),
            "currency": .string(before.currency),
            "before": Self.summary(of: before),
            "after": Self.summary(of: after),
            "saved": false,
        ])
    }

    private static func summary(of goal: SavingsGoal) -> JSONValue {
        ["name": .string(goal.name), "target": .number(FinanceToolkitCompute.round2(goal.targetAmount)), "deadline": day(goal.deadline)]
    }

    private static func summary(of debt: PersonalDebt) -> JSONValue {
        [
            "due_date": day(debt.dueDate),
            "note": debt.note.map(JSONValue.string) ?? .null,
            "settled": .bool(debt.settledAt != nil),
            "left": .number(FinanceToolkitCompute.round2(debt.remaining)),
        ]
    }

    /// What a goal or debt change will do (FinanceToolkit.describe).
    func describePlanChange(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .goalChange(let before, let after):
            return ["type": "goal_change", "goal_id": .string(before.id), "before": Self.summary(of: before), "after": Self.summary(of: after)]
        case .debtChange(let before, let after):
            return ["type": "debt_change", "debt_id": .string(before.id), "before": Self.summary(of: before), "after": Self.summary(of: after)]
        default:
            return .null
        }
    }
}
