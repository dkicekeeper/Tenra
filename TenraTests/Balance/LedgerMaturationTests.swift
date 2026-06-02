//
//  LedgerMaturationTests.swift
//  TenraTests
//
//  Covers the day-rollover decision that drives realized-figure recomputation,
//  plus the once-per-day guard on the store orchestration.
//

import Testing
import Foundation
@testable import Tenra

struct LedgerMaturationDecisionTests {

    private func date(_ s: String) -> Date {
        DateFormatters.dateFormatter.date(from: s)!
    }

    @Test("recalc is due when it has never run")
    func dueWhenNeverRun() {
        #expect(LedgerMaturation.shouldRecalculate(now: date("2026-05-25"), lastRecalcKey: nil))
    }

    @Test("recalc is NOT due twice on the same day")
    func notDueSameDay() {
        let now = date("2026-05-25")
        let key = LedgerMaturation.dayKey(for: now)
        #expect(!LedgerMaturation.shouldRecalculate(now: now, lastRecalcKey: key))
    }

    @Test("recalc is due after the day rolls over")
    func dueAfterRollover() {
        let yesterday = LedgerMaturation.dayKey(for: date("2026-05-24"))
        #expect(LedgerMaturation.shouldRecalculate(now: date("2026-05-25"), lastRecalcKey: yesterday))
    }

    // MARK: - isMatured (the targeted-maturation predicate)

    @Test("isMatured: a tx dated inside (last, today] has matured")
    func maturedInsideWindow() {
        #expect(LedgerMaturation.isMatured(dateKey: "2026-05-25", since: "2026-05-24", through: "2026-05-25"))
        // Multi-day gap: a tx two days ago, last run three days ago.
        #expect(LedgerMaturation.isMatured(dateKey: "2026-05-23", since: "2026-05-22", through: "2026-05-25"))
    }

    @Test("isMatured: a tx dated on/before the last run is already realized, NOT matured")
    func notMaturedAtOrBeforeLast() {
        #expect(!LedgerMaturation.isMatured(dateKey: "2026-05-24", since: "2026-05-24", through: "2026-05-25"))
        #expect(!LedgerMaturation.isMatured(dateKey: "2026-05-01", since: "2026-05-24", through: "2026-05-25"))
    }

    @Test("isMatured: a tx dated after today is still in the future, NOT matured")
    func notMaturedAfterToday() {
        #expect(!LedgerMaturation.isMatured(dateKey: "2026-05-26", since: "2026-05-24", through: "2026-05-25"))
    }
}

@MainActor
struct LedgerMaturationStoreTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        return TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
    }

    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ledger.\(UUID().uuidString)")!
    }

    private func date(_ s: String) -> Date {
        DateFormatters.dateFormatter.date(from: s)!
    }

    private static func bankAccount() -> Account {
        Account(id: "a1", name: "Bank", currency: "KZT", createdDate: Date(), balance: 0)
    }

    private static func tx(_ date: String) -> Transaction {
        Transaction(id: "t_\(date)", date: date, description: "",
                    amount: 10, currency: "KZT", type: .income, category: "X", accountId: "a1")
    }

    @Test("first run stamps today's date key; second run same day is a no-op")
    func runsOncePerDay() async {
        let store = Self.makeStore()
        store.accounts = [Account(id: "a1", name: "Bank", currency: "KZT", createdDate: Date(), balance: 0)]
        store.rebuildAccountById()
        let defaults = Self.freshDefaults()
        let now = DateFormatters.dateFormatter.date(from: "2026-05-25")!

        #expect(defaults.string(forKey: "lastLedgerRecalcDate") == nil)
        await store.recalculateLedgerIfDayChanged(now: now, defaults: defaults)
        #expect(defaults.string(forKey: "lastLedgerRecalcDate") == LedgerMaturation.dayKey(for: now))

        // Second call on the same day must remain stamped (idempotent, no crash).
        await store.recalculateLedgerIfDayChanged(now: now, defaults: defaults)
        #expect(defaults.string(forKey: "lastLedgerRecalcDate") == LedgerMaturation.dayKey(for: now))
    }

    @Test("does nothing before accounts are loaded")
    func noopWhenNoAccounts() async {
        let store = Self.makeStore()
        let defaults = Self.freshDefaults()
        await store.recalculateLedgerIfDayChanged(now: Date(), defaults: defaults)
        #expect(defaults.string(forKey: "lastLedgerRecalcDate") == nil)
    }

    @Test("rollover with NOTHING matured skips the recompute but still advances the day key")
    func skipsWhenNothingMatured() async {
        let store = Self.makeStore()
        store.accounts = [Self.bankAccount()]
        store.rebuildAccountById()
        store.transactions = [Self.tx("2026-05-01")] // realized long ago — nothing matures
        let defaults = Self.freshDefaults()
        defaults.set("2026-05-24", forKey: "lastLedgerRecalcDate") // ran yesterday
        let before = store.categoriesMutationVersion

        await store.recalculateLedgerIfDayChanged(now: date("2026-05-25"), defaults: defaults)

        // categoriesMutationVersion only bumps on the heavy recompute path → unchanged = skipped.
        #expect(store.categoriesMutationVersion == before)
        #expect(defaults.string(forKey: "lastLedgerRecalcDate") == LedgerMaturation.dayKey(for: date("2026-05-25")))
    }

    @Test("rollover WITH a matured tx runs the recompute")
    func runsWhenSomethingMatured() async {
        let store = Self.makeStore()
        store.accounts = [Self.bankAccount()]
        store.rebuildAccountById()
        store.transactions = [Self.tx("2026-05-25")] // dated today — was future yesterday, matures now
        let defaults = Self.freshDefaults()
        defaults.set("2026-05-24", forKey: "lastLedgerRecalcDate")
        let before = store.categoriesMutationVersion

        await store.recalculateLedgerIfDayChanged(now: date("2026-05-25"), defaults: defaults)

        #expect(store.categoriesMutationVersion == before + 1)
        #expect(defaults.string(forKey: "lastLedgerRecalcDate") == LedgerMaturation.dayKey(for: date("2026-05-25")))
    }

    @Test("first launch (no prior key) runs the repair recompute even with no future tx")
    func firstLaunchRunsRepair() async {
        let store = Self.makeStore()
        store.accounts = [Self.bankAccount()]
        store.rebuildAccountById()
        store.transactions = [Self.tx("2026-05-01")]
        let defaults = Self.freshDefaults() // no prior key
        let before = store.categoriesMutationVersion

        await store.recalculateLedgerIfDayChanged(now: date("2026-05-25"), defaults: defaults)

        #expect(store.categoriesMutationVersion == before + 1)
    }
}
