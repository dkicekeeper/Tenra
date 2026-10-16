//
//  DebtStore.swift
//  Tenra
//
//  Personal debts (docs/domains/goals-and-debts.md): the list the Finances card, the debt
//  screens and Ten read, and every change to it. A repayment that covers what is left settles
//  the debt; deleting that repayment opens it again. Settling by hand (the rest forgiven) and
//  reopening are the person's own choices.
//
//  Kept in CoreData v15 through DebtRepository; nil keeps the debts in memory only (previews,
//  tests). The list reloads when the store is replaced (delete all data, a restored backup).
//  Debts are Tenra Pro: the screens gate adding one, the store does not.
//

import Foundation
import Observation

@Observable
final class DebtStore {
    /// Oldest first.
    private(set) var debts: [PersonalDebt] = []
    /// The kept debts have been read: an empty list means there are none.
    private(set) var isLoaded: Bool

    @ObservationIgnored private let repository: DebtRepository?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var resetObserver: NSObjectProtocol?

    init(repository: DebtRepository?) {
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

    /// Reads the kept debts, once; later calls wait for that read.
    func load() async {
        if let loading { return await loading.value }
        guard let repository else { return }
        let task = Task { @MainActor in
            self.debts = await repository.all()
            self.isLoaded = true
        }
        loading = task
        await task.value
    }

    func debt(id: String) -> PersonalDebt? {
        debts.first { $0.id == id }
    }

    /// Open debts one way, the soonest due first, those without a date after, oldest first.
    func open(_ direction: DebtDirection) -> [PersonalDebt] {
        debts
            .filter { $0.direction == direction && !$0.isSettled }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?) where l != r: return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.date < rhs.date
                }
            }
    }

    /// Settled debts, the latest first.
    var settled: [PersonalDebt] {
        debts.filter(\.isSettled).sorted { ($0.settledAt ?? .distantPast) > ($1.settledAt ?? .distantPast) }
    }

    /// What is still owed one way, in `currency`.
    func total(_ direction: DebtDirection, in currency: String) -> Double {
        open(direction).reduce(0) { sum, debt in
            sum + (CurrencyConverter.convertSync(amount: debt.remaining, from: debt.currency, to: currency) ?? debt.remaining)
        }
    }

    // MARK: - Changes

    func add(_ debt: PersonalDebt) async {
        debts.append(debt)
        await repository?.save(debt)
    }

    /// Writes the debt over its earlier copy.
    func update(_ debt: PersonalDebt) async {
        guard let index = debts.firstIndex(where: { $0.id == debt.id }) else { return }
        debts[index] = debt
        await repository?.save(debt)
    }

    func delete(id: String) async {
        debts.removeAll { $0.id == id }
        await repository?.delete(id: id)
    }

    /// Adds a repayment; one that covers what is left settles the debt on its date.
    func addRepayment(_ repayment: DebtRepayment, to debtId: String) async {
        guard var debt = debt(id: debtId) else { return }
        debt.repayments.append(repayment)
        debt.repayments.sort { $0.date < $1.date }
        if debt.settledAt == nil, debt.isCovered {
            debt.settledAt = repayment.date
        }
        await update(debt)
    }

    /// Deletes a repayment; a debt its repayments settled is open again once they no longer
    /// cover it, whichever one goes. One settled by hand (the rest forgiven) never was covered,
    /// and stays settled.
    func deleteRepayment(id: String, from debtId: String) async {
        guard var debt = debt(id: debtId), debt.repayments.contains(where: { $0.id == id }) else { return }
        let wasCovered = debt.isCovered
        debt.repayments.removeAll { $0.id == id }
        if debt.settledAt != nil, wasCovered, !debt.isCovered {
            debt.settledAt = nil
        }
        await update(debt)
    }

    /// Settles the debt by hand (returned outside the app, or the rest forgiven).
    func settle(id: String, at date: Date = Date()) async {
        guard var debt = debt(id: id), debt.settledAt == nil else { return }
        debt.settledAt = date
        await update(debt)
    }

    func reopen(id: String) async {
        guard var debt = debt(id: id), debt.settledAt != nil else { return }
        debt.settledAt = nil
        await update(debt)
    }
}
