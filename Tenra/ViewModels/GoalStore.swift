//
//  GoalStore.swift
//  Tenra
//
//  The savings goals (docs/domains/goals-and-debts.md): the list the Finances card, the goal
//  screens and Ten read, and every change to it. A goal's saved amount is its linked account's
//  balance (read live from BalanceCoordinator through `accountBalance`, converted to the goal's
//  currency) or the sum of its contributions; GoalProgress does the arithmetic on top.
//
//  Kept in CoreData v15 through GoalRepository; nil keeps the goals in memory only (previews,
//  tests). The list reloads when the store is replaced (delete all data, a restored backup).
//

import Foundation
import Observation

@Observable
final class GoalStore {
    /// An account's balance in its own currency.
    struct AccountBalance: Equatable {
        var amount: Double
        var currency: String
    }

    /// In list order.
    private(set) var goals: [SavingsGoal] = []
    /// The kept goals have been read: an empty list means there are none.
    private(set) var isLoaded: Bool

    /// A linked account's live balance; nil when the account is gone. Set by AppCoordinator.
    @ObservationIgnored var accountBalance: (String) -> AccountBalance? = { _ in nil }

    @ObservationIgnored private let repository: GoalRepository?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var resetObserver: NSObjectProtocol?

    init(repository: GoalRepository?) {
        self.repository = repository
        self.isLoaded = repository == nil
        if let stack = repository?.stack {
            resetObserver = NotificationCenter.default.addObserver(
                forName: CoreDataStack.storeDidResetNotification,
                object: stack,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = nil
                    Task { await self.load() }
                }
            }
        }
    }

    /// Reads the kept goals, once; later calls wait for that read.
    func load() async {
        if let loading { return await loading.value }
        guard let repository else { return }
        let task = Task { @MainActor in
            self.goals = await repository.all()
            self.isLoaded = true
        }
        loading = task
        await task.value
    }

    func goal(id: String) -> SavingsGoal? {
        goals.first { $0.id == id }
    }

    // MARK: - Progress

    /// What is saved, in the goal's currency: the linked account's balance (never below zero),
    /// or the contributions when it has no account or the account is gone.
    func saved(for goal: SavingsGoal) -> Double {
        if let accountId = goal.linkedAccountId, let balance = accountBalance(accountId) {
            let amount = balance.currency == goal.currency
                ? balance.amount
                : CurrencyConverter.convertSync(amount: balance.amount, from: balance.currency, to: goal.currency) ?? balance.amount
            return max(0, amount)
        }
        return goal.contributed
    }

    /// The goal follows an account that still exists.
    func followsAccount(_ goal: SavingsGoal) -> Bool {
        guard let accountId = goal.linkedAccountId else { return false }
        return accountBalance(accountId) != nil
    }

    func status(for goal: SavingsGoal, today: Date = Date()) -> GoalProgress.Status {
        GoalProgress.status(target: goal.targetAmount, saved: saved(for: goal), deadline: goal.deadline, today: today)
    }

    /// Everything saved towards the goals, in `currency`; an account several goals follow
    /// counts once.
    func totalSaved(in currency: String) -> Double {
        var countedAccounts = Set<String>()
        return goals.reduce(0) { sum, goal in
            if followsAccount(goal), let accountId = goal.linkedAccountId,
               !countedAccounts.insert(accountId).inserted {
                return sum
            }
            let amount = saved(for: goal)
            return sum + (CurrencyConverter.convertSync(amount: amount, from: goal.currency, to: currency) ?? amount)
        }
    }

    // MARK: - Changes

    /// Adds a goal at the end of the list.
    func add(_ goal: SavingsGoal) async {
        var goal = goal
        goal.order = (goals.map(\.order).max() ?? -1) + 1
        goals.append(goal)
        await repository?.save(goal)
    }

    /// Writes the goal over its earlier copy.
    func update(_ goal: SavingsGoal) async {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal
        await repository?.save(goal)
    }

    func delete(id: String) async {
        goals.removeAll { $0.id == id }
        await repository?.delete(id: id)
    }

    /// The goals of one list (in progress, or reached) in the order the person dragged them to
    /// (DesignKit 8.0.0's list): they take that list's places among all the goals, in memory at
    /// once (the list moves while the finger does), then kept.
    func reorder(_ orderedIds: [String]) async {
        let places = orderedIds.compactMap { id in goals.first { $0.id == id }?.order }.sorted()
        var moved: [SavingsGoal] = []
        for (id, place) in zip(orderedIds, places) {
            guard let i = goals.firstIndex(where: { $0.id == id }), goals[i].order != place else { continue }
            goals[i].order = place
            moved.append(goals[i])
        }
        goals.sort { $0.order < $1.order }
        for goal in moved {
            await repository?.save(goal)
        }
    }

    func addContribution(_ contribution: GoalContribution, to goalId: String) async {
        guard var goal = goal(id: goalId) else { return }
        goal.contributions.append(contribution)
        goal.contributions.sort { $0.date < $1.date }
        await update(goal)
    }

    func deleteContribution(id: String, from goalId: String) async {
        guard var goal = goal(id: goalId) else { return }
        goal.contributions.removeAll { $0.id == id }
        await update(goal)
    }

    /// Notes when the goal is reached, or that it fell back below the target. Returns true when
    /// it was reached just now (the screen celebrates once).
    @discardableResult
    func refreshReached(goalId: String, now: Date = Date()) async -> Bool {
        guard var goal = goal(id: goalId) else { return false }
        let isReached = status(for: goal, today: now).isReached
        switch (isReached, goal.reachedAt) {
        case (true, nil):
            goal.reachedAt = now
            await update(goal)
            return true
        case (false, _?):
            goal.reachedAt = nil
            await update(goal)
            return false
        default:
            return false
        }
    }

    /// Notes `reachedAt` on every goal, so a goal its linked account carried over the target
    /// keeps its date without its screen being open. Runs when the goals are read and when the
    /// app comes to the front; the goal's screen still celebrates one reached while it is open.
    func refreshAllReached(now: Date = Date()) async {
        for id in goals.map(\.id) {
            await refreshReached(goalId: id, now: now)
        }
    }
}
