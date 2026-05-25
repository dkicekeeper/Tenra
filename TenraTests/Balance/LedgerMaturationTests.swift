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
}
