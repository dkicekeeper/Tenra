//
//  PlanToolsTests.swift
//  TenraTests
//
//  Ten and savings goals and personal debts (FinanceToolkit+Plans.swift): <app_context> lists
//  goals and open debts by id and name without amounts; get_goals and get_debts report the
//  app's own progress; draft_goal, draft_goal_contribution, draft_debt and
//  draft_debt_repayment file drafts that save through GoalStore / DebtStore and undo; a goal
//  that follows an account takes a transfer, not a contribution; a new debt needs Tenra Pro;
//  a repayment is capped at what is left and settles the debt. Ten writes first about a debt
//  due tomorrow and a goal behind its schedule. Amounts are KZT, so no shared FX state is
//  involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct PlanToolsTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    private struct Setup {
        let toolkit: FinanceToolkit
        let book: AgentDraftBook
        /// Retained: AccountsViewModel keeps it weakly.
        let store: TransactionStore
        let goals: GoalStore
        let debts: DebtStore
    }

    /// Tenra Pro that can end between a draft and its Save.
    private final class ProFlag {
        var isPro = true
    }

    private static func make(isPro: Bool = true, pro: ProFlag? = nil) -> Setup {
        let checkPro: () -> Bool = { pro?.isPro ?? isPro }
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_000),
            Account(id: "acc_deposit", name: "Deposit", currency: "KZT", balance: 400_000),
        ]
        let goals = GoalStore(repository: nil)
        goals.accountBalance = { [weak store] id in
            store?.accounts.first { $0.id == id }.map { GoalStore.AccountBalance(amount: $0.balance, currency: $0.currency) }
        }
        let debts = DebtStore(repository: nil)
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { try await AgentDraftBook.Writer.savePlan($0, goals: goals, debts: debts, isPro: checkPro) },
            undo: { await AgentDraftBook.Writer.undoPlan($0, goals: goals, debts: debts) }
        ))
        let toolkit = FinanceToolkit(
            store: store,
            drafts: book,
            goals: goals,
            debts: debts,
            isPro: checkPro,
            learned: VoiceLearningStore(defaults: defaults),
            now: { now }
        )
        return Setup(toolkit: toolkit, book: book, store: store, goals: goals, debts: debts)
    }

    private static func day(_ key: String) -> Date {
        FastDateParser.date(from: key)!
    }

    // MARK: - Context

    @Test func theContextListsGoalsAndOpenDebtsWithoutAmounts() {
        let snapshot = AgentContextSnapshot(
            today: Self.now,
            timeZone: TimeZone(identifier: "UTC")!,
            locale: "ru",
            baseCurrency: "KZT",
            accounts: [],
            categories: [],
            goals: [.init(id: "g1", name: "Машина", currency: "KZT")],
            debts: [.init(id: "d1", person: "Асхат", direction: "owed_to_me", currency: "KZT")]
        )
        let text = AgentContextBuilder.text(for: snapshot)
        #expect(text.contains(#"savings goals: g1 "Машина" (KZT)"#))
        #expect(text.contains(#"open debts: d1 "Асхат" (owed_to_me, KZT)"#))

        let none = AgentContextBuilder.text(for: AgentContextSnapshot(
            today: Self.now, timeZone: TimeZone(identifier: "UTC")!, locale: "ru", baseCurrency: "KZT", accounts: [], categories: []
        ))
        #expect(!none.contains("savings goals"))
        #expect(!none.contains("open debts"))
    }

    @Test func theStoreContextLeavesSettledDebtsOut() {
        let setup = Self.make()
        let open = PersonalDebt(id: "d_open", direction: .iOwe, person: "Mum", amount: 100, currency: "KZT")
        let settled = PersonalDebt(id: "d_done", direction: .owedToMe, person: "Askhat", amount: 50, currency: "KZT", settledAt: Self.now)
        let snapshot = AgentContextSnapshot(store: setup.store, debts: [open, settled], now: Self.now)
        #expect(snapshot.debts.map(\.id) == ["d_open"])
        #expect(snapshot.debts.first?.direction == "i_owe")
    }

    // MARK: - Read

    @Test func getGoalsReportsTheAppsProgress() async throws {
        let setup = Self.make()
        await setup.goals.add(SavingsGoal(
            id: "g_trip", name: "Отпуск", targetAmount: 600_000, currency: "KZT",
            deadline: Self.day("2027-04-28"),
            contributions: [GoalContribution(amount: 150_000, date: Self.now)]
        ))
        await setup.goals.add(SavingsGoal(id: "g_car", name: "Машина", targetAmount: 1_000_000, currency: "KZT", linkedAccountId: "acc_deposit"))

        let output = await setup.toolkit.execute(name: "get_goals", input: [:])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result.value(atPath: "goals.0.saved")?.numberValue == 150_000)
        #expect(result.value(atPath: "goals.0.left")?.numberValue == 450_000)
        #expect(result.value(atPath: "goals.0.months_left")?.numberValue == 6)
        #expect(result.value(atPath: "goals.0.monthly")?.numberValue == 75_000)
        // The car follows the deposit's balance.
        #expect(result.value(atPath: "goals.1.saved")?.numberValue == 400_000)
        #expect(result.value(atPath: "goals.1.account_id")?.stringValue == "acc_deposit")
        #expect(result["total_saved"]?.numberValue == 550_000)
    }

    @Test func getDebtsReportsOpenDebtsAndTotals() async throws {
        let setup = Self.make()
        await setup.debts.add(PersonalDebt(id: "d_askhat", direction: .owedToMe, person: "Асхат", amount: 50_000, currency: "KZT", dueDate: Self.day("2026-10-20")))
        await setup.debts.addRepayment(DebtRepayment(amount: 20_000, date: Self.day("2026-10-10")), to: "d_askhat")
        await setup.debts.add(PersonalDebt(id: "d_mum", direction: .iOwe, person: "Мама", amount: 100_000, currency: "KZT"))

        let output = await setup.toolkit.execute(name: "get_debts", input: [:])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result.value(atPath: "debts.0.remaining")?.numberValue == 30_000)
        #expect(result.value(atPath: "debts.0.overdue")?.boolValue == true)
        #expect(result.value(atPath: "debts.1.direction")?.stringValue == "i_owe")
        #expect(result["owed_to_me"]?.numberValue == 30_000)
        #expect(result["i_owe"]?.numberValue == 100_000)
    }

    // MARK: - Drafts

    @Test func draftGoalSavesAGoalAndUndoRemovesIt() async throws {
        let setup = Self.make()
        let output = await setup.toolkit.execute(name: "draft_goal", input: [
            "name": "Ноутбук", "target": 600_000, "currency": .null, "deadline": "2027-04-28", "account": .null, "already_saved": 120_000,
        ])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["draft_id"] == "draft_1")
        #expect(result["left"]?.numberValue == 480_000)
        #expect(result["monthly"]?.numberValue == 80_000)
        #expect(setup.goals.goals.isEmpty)

        await setup.book.save("draft_1")
        #expect(setup.goals.goals.map(\.name) == ["Ноутбук"])
        #expect(setup.goals.goals.first?.contributed == 120_000)
        #expect(setup.goals.goals.first?.currency == setup.store.baseCurrency)
        await setup.book.undo("draft_1")
        #expect(setup.goals.goals.isEmpty)

        // A past deadline and an unknown account are refused.
        let late = await setup.toolkit.execute(name: "draft_goal", input: ["name": "X", "target": 10, "currency": .null, "deadline": "2026-01-01", "account": .null, "already_saved": .null])
        #expect(late.error != nil)
        let nowhere = await setup.toolkit.execute(name: "draft_goal", input: ["name": "X", "target": 10, "currency": .null, "deadline": .null, "account": "acc_none", "already_saved": .null])
        #expect(nowhere.error != nil)
    }

    @Test func aGoalWithAnAccountTakesATransferNotAContribution() async throws {
        let setup = Self.make()
        await setup.goals.add(SavingsGoal(id: "g_car", name: "Машина", targetAmount: 1_000_000, currency: "KZT", linkedAccountId: "acc_deposit"))
        await setup.goals.add(SavingsGoal(id: "g_trip", name: "Отпуск", targetAmount: 100_000, currency: "KZT"))

        let linked = await setup.toolkit.execute(name: "draft_goal_contribution", input: ["goal": "g_car", "amount": 5_000, "date": .null, "note": .null])
        #expect(linked.error?.contains("draft_transactions") == true)

        let output = await setup.toolkit.execute(name: "draft_goal_contribution", input: ["goal": "g_trip", "amount": 100_000, "date": .null, "note": "премия"])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["reaches_target"]?.boolValue == true)
        let draftId = try #require(result["draft_id"]?.stringValue)
        await setup.book.save(draftId)
        #expect(setup.goals.goal(id: "g_trip")?.contributed == 100_000)
        await setup.book.undo(draftId)
        #expect(setup.goals.goal(id: "g_trip")?.contributions.isEmpty == true)
    }

    @Test func aNewDebtNeedsPro() async throws {
        let free = Self.make(isPro: false)
        let refused = await free.toolkit.execute(name: "draft_debt", input: [
            "direction": "owed_to_me", "person": "Ерлан", "amount": 30_000, "currency": .null, "date": .null, "due_date": "2026-10-30", "note": .null,
        ])
        #expect(refused.error?.contains("Tenra Pro") == true)
        #expect(free.book.drafts.isEmpty)

        let pro = Self.make()
        let output = await pro.toolkit.execute(name: "draft_debt", input: [
            "direction": "owed_to_me", "person": "Ерлан", "amount": 30_000, "currency": .null, "date": .null, "due_date": "2026-10-30", "note": .null,
        ])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["due_date"] == "2026-10-30")
        await pro.book.save("draft_1")
        #expect(pro.debts.open(.owedToMe).map(\.person) == ["Ерлан"])
        await pro.book.undo("draft_1")
        #expect(pro.debts.debts.isEmpty)
    }

    @Test func aRepaymentIsCappedAndSettlesTheDebt() async throws {
        // Repaying a kept debt needs no Pro.
        let setup = Self.make(isPro: false)
        await setup.debts.add(PersonalDebt(id: "d_askhat", direction: .owedToMe, person: "Асхат", amount: 50_000, currency: "KZT"))

        let tooMuch = await setup.toolkit.execute(name: "draft_debt_repayment", input: ["debt": "d_askhat", "amount": 60_000, "date": .null, "note": .null])
        #expect(tooMuch.error != nil)

        // No amount: everything that is left; by name works too.
        let output = await setup.toolkit.execute(name: "draft_debt_repayment", input: ["debt": "асхат", "amount": .null, "date": .null, "note": .null])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["amount"]?.numberValue == 50_000)
        #expect(result["settles"]?.boolValue == true)
        let draftId = try #require(result["draft_id"]?.stringValue)
        await setup.book.save(draftId)
        #expect(setup.debts.debt(id: "d_askhat")?.isSettled == true)
        await setup.book.undo(draftId)
        #expect(setup.debts.debt(id: "d_askhat")?.isSettled == false)
        #expect(setup.debts.debt(id: "d_askhat")?.repayments.isEmpty == true)
    }

    @Test func aSecondRepaymentDraftCannotOverRepay() async throws {
        let setup = Self.make()
        await setup.debts.add(PersonalDebt(id: "d_askhat", direction: .owedToMe, person: "Асхат", amount: 50_000, currency: "KZT"))
        // Both fit in what is left when Ten drafts them.
        let first = await setup.toolkit.execute(name: "draft_debt_repayment", input: ["debt": "d_askhat", "amount": 30_000, "date": .null, "note": .null])
        let second = await setup.toolkit.execute(name: "draft_debt_repayment", input: ["debt": "d_askhat", "amount": 30_000, "date": .null, "note": .null])
        let firstId = try #require(first.value?["draft_id"]?.stringValue)
        let secondId = try #require(second.value?["draft_id"]?.stringValue)

        await setup.book.save(firstId)
        await setup.book.save(secondId)

        // The second no longer fits after the first: nothing written, the debt stays open.
        #expect(setup.book.states[secondId] == .failed)
        let debt = try #require(setup.debts.debt(id: "d_askhat"))
        #expect(debt.repayments.count == 1)
        #expect(debt.remaining == 20_000)
        #expect(debt.isSettled == false)
    }

    @Test func aDebtDraftNeedsProStillAtSave() async throws {
        let pro = ProFlag()
        let setup = Self.make(pro: pro)
        let output = await setup.toolkit.execute(name: "draft_debt", input: [
            "direction": "owed_to_me", "person": "Ерлан", "amount": 30_000, "currency": .null, "date": .null, "due_date": .null, "note": .null,
        ])
        let draftId = try #require(output.value?["draft_id"]?.stringValue, "\(output.error ?? "")")

        // Pro ends before the card's Save.
        pro.isPro = false
        await setup.book.save(draftId)

        #expect(setup.book.states[draftId] == .failed)
        #expect(setup.debts.debts.isEmpty)
    }

    @Test func describeNamesWhatAPlanDraftWrites() {
        let setup = Self.make()
        let debt = PersonalDebt(direction: .iOwe, person: "Mum", amount: 100, currency: "KZT", date: Self.day("2026-10-01"))
        let described = setup.toolkit.describe(.debt(debt))
        #expect(described["type"] == "debt")
        #expect(described["direction"] == "i_owe")
        #expect(described["date"] == "2026-10-01")
    }

    // MARK: - Ten writes first

    @Test func aDebtDueTomorrowBecomesANoteOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Self.now))!
        let due = PersonalDebt(id: "d1", direction: .owedToMe, person: "Асхат", amount: 30_000, currency: "KZT", dueDate: tomorrow)
        let later = PersonalDebt(id: "d2", direction: .iOwe, person: "Мама", amount: 10, currency: "KZT", dueDate: calendar.date(byAdding: .day, value: 5, to: tomorrow))
        var settled = due
        settled.id = "d3"
        settled.settledAt = Self.now

        let notices = AssistantNotices.debtsDue([due, later, settled], now: Self.now, calendar: calendar)
        #expect(notices.map(\.subjectId) == ["d1"])
        #expect(notices.first?.kind == .debt)
        #expect(notices.first?.modelText.contains("\"debt_id\":\"d1\"") == true)
    }

    @Test func aGoalBehindItsScheduleBecomesANote() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let started = calendar.date(byAdding: .month, value: -6, to: Self.now)!
        let deadline = calendar.date(byAdding: .month, value: 6, to: Self.now)!
        // Half the time gone, a tenth saved: behind.
        let behind = SavingsGoal(id: "g_behind", name: "Car", targetAmount: 1_000, currency: "KZT", deadline: deadline, createdAt: started)
        // Half the time gone, half saved: on track.
        let onTrack = SavingsGoal(id: "g_ok", name: "Trip", targetAmount: 1_000, currency: "KZT", deadline: deadline, createdAt: started)
        // Started last week: too early to tell.
        let fresh = SavingsGoal(id: "g_new", name: "Bike", targetAmount: 1_000, currency: "KZT", deadline: deadline, createdAt: calendar.date(byAdding: .day, value: -7, to: Self.now)!)

        let saved: [String: Double] = ["g_behind": 100, "g_ok": 500, "g_new": 0]
        let notices = AssistantNotices.goalsBehind([behind, onTrack, fresh], saved: { saved[$0.id] ?? 0 }, now: Self.now, calendar: calendar)
        #expect(notices.map(\.subjectId) == ["g_behind"])
        #expect(notices.first?.kind == .goal)
        #expect(notices.first?.id.hasPrefix("goal:g_behind:2026-10") == true)
    }
}
