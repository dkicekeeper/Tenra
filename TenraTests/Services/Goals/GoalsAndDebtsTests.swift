//
//  GoalsAndDebtsTests.swift
//  TenraTests
//
//  Savings goals and personal debts (docs/domains/goals-and-debts.md, CoreData v15): months
//  to a deadline count the current one, a goal says what is left and what to put aside each
//  month, it follows its linked account or its contributions, and its being reached is noted
//  once. A repayment that covers the rest settles a debt and deleting it opens the debt again;
//  open debts sort by due date and total one way. Both repositories keep their rows across a
//  new store over the same stack.
//

import CoreData
import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct GoalsAndDebtsTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeStack() throws -> CoreDataStack {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return CoreDataStack(container: container)
    }

    // MARK: - GoalProgress

    @Test func monthsToADeadlineCountTheCurrentOne() {
        let today = Self.day(2026, 10, 14)
        #expect(GoalProgress.months(from: today, to: Self.day(2026, 10, 31), calendar: Self.calendar) == 1)
        #expect(GoalProgress.months(from: today, to: Self.day(2026, 10, 14), calendar: Self.calendar) == 1)
        #expect(GoalProgress.months(from: today, to: Self.day(2027, 4, 14), calendar: Self.calendar) == 6)
        #expect(GoalProgress.months(from: today, to: Self.day(2027, 4, 20), calendar: Self.calendar) == 7)
        #expect(GoalProgress.months(from: today, to: Self.day(2026, 10, 13), calendar: Self.calendar) == nil)
    }

    @Test func aGoalSaysWhatIsLeftAndWhatToPutAsideEachMonth() {
        let today = Self.day(2026, 10, 14)
        let status = GoalProgress.status(target: 1_200_000, saved: 300_000, deadline: Self.day(2027, 4, 14), today: today, calendar: Self.calendar)
        #expect(status.left == 900_000)
        #expect(status.monthsLeft == 6)
        #expect(status.monthly == 150_000)
        #expect(abs(status.fraction - 0.25) < 1e-9)
        #expect(!status.isReached)
        #expect(!status.isOverdue)

        let reached = GoalProgress.status(target: 100, saved: 120, deadline: Self.day(2026, 1, 1), today: today, calendar: Self.calendar)
        #expect(reached.isReached)
        #expect(reached.left == 0)
        #expect(reached.fraction == 1)
        #expect(reached.monthly == nil)
        #expect(!reached.isOverdue)

        let late = GoalProgress.status(target: 100, saved: 10, deadline: Self.day(2026, 10, 13), today: today, calendar: Self.calendar)
        #expect(late.isOverdue)
        #expect(late.monthly == nil)
        #expect(late.left == 90)

        let noDate = GoalProgress.status(target: 100, saved: 10, deadline: nil, today: today, calendar: Self.calendar)
        #expect(noDate.monthsLeft == nil)
        #expect(!noDate.isOverdue)
    }

    // MARK: - GoalStore

    @Test func aGoalFollowsItsAccountOrItsContributions() async {
        let store = GoalStore(repository: nil)
        store.accountBalance = { id in id == "acc" ? GoalStore.AccountBalance(amount: 500, currency: "KZT") : nil }
        let manual = SavingsGoal(name: "Bike", targetAmount: 1000, currency: "KZT", contributions: [
            GoalContribution(amount: 200, date: Self.day(2026, 9, 1)),
            GoalContribution(amount: 100, date: Self.day(2026, 10, 1)),
        ])
        let linked = SavingsGoal(name: "Car", targetAmount: 1000, currency: "KZT", linkedAccountId: "acc")
        let orphan = SavingsGoal(name: "Old", targetAmount: 1000, currency: "KZT", linkedAccountId: "gone", contributions: [
            GoalContribution(amount: 50, date: Self.day(2026, 9, 1)),
        ])
        await store.add(manual)
        await store.add(linked)
        await store.add(orphan)

        #expect(store.saved(for: manual) == 300)
        #expect(store.saved(for: linked) == 500)
        // The account is gone: the goal counts its contributions again.
        #expect(store.saved(for: orphan) == 50)
        #expect(store.followsAccount(linked))
        #expect(!store.followsAccount(orphan))
        #expect(store.goals.map(\.order) == [0, 1, 2])

        // Two goals on one account count it once in the total.
        await store.add(SavingsGoal(name: "Car again", targetAmount: 2000, currency: "KZT", linkedAccountId: "acc"))
        #expect(store.totalSaved(in: "KZT") == 300 + 500 + 50)

        // An overdrawn account saves nothing.
        store.accountBalance = { _ in GoalStore.AccountBalance(amount: -100, currency: "KZT") }
        #expect(store.saved(for: linked) == 0)
    }

    @Test func reachingAGoalIsNotedOnce() async throws {
        let store = GoalStore(repository: nil)
        await store.add(SavingsGoal(id: "g", name: "Phone", targetAmount: 100, currency: "KZT"))
        #expect(await store.refreshReached(goalId: "g") == false)

        await store.addContribution(GoalContribution(amount: 100, date: Self.day(2026, 10, 1)), to: "g")
        #expect(await store.refreshReached(goalId: "g") == true)
        #expect(store.goal(id: "g")?.reachedAt != nil)
        #expect(await store.refreshReached(goalId: "g") == false)

        // Below the target again: no longer reached, and nothing to celebrate.
        let contribution = try #require(store.goal(id: "g")?.contributions.first)
        await store.deleteContribution(id: contribution.id, from: "g")
        #expect(await store.refreshReached(goalId: "g") == false)
        #expect(store.goal(id: "g")?.reachedAt == nil)
    }

    // MARK: - DebtStore

    @Test func aRepaymentThatCoversTheRestSettlesTheDebt() async {
        let store = DebtStore(repository: nil)
        await store.add(PersonalDebt(id: "d", direction: .owedToMe, person: "Askhat", amount: 50_000, currency: "KZT"))

        await store.addRepayment(DebtRepayment(id: "r1", amount: 20_000, date: Self.day(2026, 10, 1)), to: "d")
        #expect(store.debt(id: "d")?.remaining == 30_000)
        #expect(store.debt(id: "d")?.isSettled == false)

        await store.addRepayment(DebtRepayment(id: "r2", amount: 30_000, date: Self.day(2026, 10, 10)), to: "d")
        #expect(store.debt(id: "d")?.settledAt == Self.day(2026, 10, 10))
        #expect(store.debt(id: "d")?.remaining == 0)
        #expect(store.debt(id: "d")?.progress == 1)

        // The repayment that settled it goes: the debt is open again.
        await store.deleteRepayment(id: "r2", from: "d")
        #expect(store.debt(id: "d")?.isSettled == false)
        #expect(store.debt(id: "d")?.remaining == 30_000)

        // Settled by hand (the rest forgiven): deleting another repayment leaves it settled.
        await store.settle(id: "d", at: Self.day(2026, 10, 12))
        await store.deleteRepayment(id: "r1", from: "d")
        #expect(store.debt(id: "d")?.isSettled == true)

        await store.reopen(id: "d")
        #expect(store.debt(id: "d")?.isSettled == false)
        #expect(store.debt(id: "d")?.remaining == 50_000)
    }

    @Test func openDebtsSortByDueDateAndTotalOneWay() async {
        let store = DebtStore(repository: nil)
        await store.add(PersonalDebt(id: "a", direction: .owedToMe, person: "A", amount: 100, currency: "KZT", date: Self.day(2026, 9, 1), dueDate: Self.day(2026, 11, 1)))
        await store.add(PersonalDebt(id: "b", direction: .owedToMe, person: "B", amount: 50, currency: "KZT", date: Self.day(2026, 9, 2), dueDate: Self.day(2026, 10, 20)))
        await store.add(PersonalDebt(id: "c", direction: .owedToMe, person: "C", amount: 30, currency: "KZT", date: Self.day(2026, 9, 3)))
        await store.add(PersonalDebt(id: "d", direction: .iOwe, person: "D", amount: 70, currency: "KZT"))
        await store.add(PersonalDebt(id: "e", direction: .owedToMe, person: "E", amount: 10, currency: "KZT", settledAt: Self.day(2026, 10, 1)))

        #expect(store.open(.owedToMe).map(\.id) == ["b", "a", "c"])
        #expect(store.open(.iOwe).map(\.id) == ["d"])
        #expect(store.settled.map(\.id) == ["e"])
        #expect(store.total(.owedToMe, in: "KZT") == 180)
        #expect(store.total(.iOwe, in: "KZT") == 70)
    }

    @Test func overdueMeansOpenAndPastItsDueDate() {
        let today = Self.day(2026, 10, 14)
        let late = PersonalDebt(direction: .owedToMe, person: "A", amount: 10, currency: "KZT", dueDate: Self.day(2026, 10, 13))
        let dueToday = PersonalDebt(direction: .owedToMe, person: "A", amount: 10, currency: "KZT", dueDate: today)
        var settled = late
        settled.settledAt = today
        #expect(late.isOverdue(today: today, calendar: Self.calendar))
        #expect(!dueToday.isOverdue(today: today, calendar: Self.calendar))
        #expect(!settled.isOverdue(today: today, calendar: Self.calendar))
    }

    // MARK: - Repositories

    @Test func goalsAndDebtsAreKeptAcrossLaunches() async throws {
        let stack = try makeStack()
        let goals = GoalStore(repository: GoalRepository(stack: stack))
        await goals.load()
        #expect(goals.isLoaded)
        #expect(goals.goals.isEmpty)
        await goals.add(SavingsGoal(
            id: "g",
            name: "Car",
            iconSource: .sfSymbol("car.fill"),
            targetAmount: 3_000_000,
            currency: "USD",
            deadline: Self.day(2027, 6, 1),
            contributions: [GoalContribution(id: "c", amount: 1000, date: Self.day(2026, 10, 1), note: "Bonus")],
            createdAt: Self.day(2026, 10, 1)
        ))

        let debts = DebtStore(repository: DebtRepository(stack: stack))
        await debts.load()
        await debts.add(PersonalDebt(id: "d", direction: .iOwe, person: "Mum", amount: 20_000, currency: "KZT", date: Self.day(2026, 10, 2), dueDate: Self.day(2026, 12, 1), note: "Rent"))
        await debts.addRepayment(DebtRepayment(id: "r", amount: 5_000, date: Self.day(2026, 10, 5)), to: "d")

        let goalsAgain = GoalStore(repository: GoalRepository(stack: stack))
        #expect(!goalsAgain.isLoaded)
        await goalsAgain.load()
        #expect(goalsAgain.goals == goals.goals)

        let debtsAgain = DebtStore(repository: DebtRepository(stack: stack))
        await debtsAgain.load()
        #expect(debtsAgain.debts == debts.debts)

        await goalsAgain.delete(id: "g")
        await debtsAgain.delete(id: "d")
        #expect(await GoalRepository(stack: stack).all().isEmpty)
        #expect(await DebtRepository(stack: stack).all().isEmpty)
    }
}
