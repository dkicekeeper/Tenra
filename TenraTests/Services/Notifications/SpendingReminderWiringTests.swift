//
//  SpendingReminderWiringTests.swift
//  TenraTests
//
//  Pins how the store tells the spending reminder about records (docs/plan-spending-reminder.md
//  §3.1): every added transaction reaches `TransactionStore.onRecorded`, the app's and the
//  background intents' alike, and a batch the store already holds reaches it not at all.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.sharedProcessState)
struct SpendingReminderWiringTests {

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

    private static func expense(id: String) -> Transaction {
        Transaction(
            id: id, date: "2026-11-05", description: "coffee", amount: 1500, currency: "KZT",
            type: .expense, category: ""
        )
    }

    @Test("One added transaction reaches onRecorded")
    func addCallsOnRecorded() async throws {
        let store = Self.makeStore()
        var recorded: [[String]] = []
        store.onRecorded = { recorded.append($0.map(\.id)) }
        _ = try await store.add(Self.expense(id: "t1"))
        #expect(recorded == [["t1"]])
    }

    @Test("A batch the store already holds is not reported again")
    func bulkAddPassesOnlyFresh() async throws {
        let store = Self.makeStore()
        var recorded: [[String]] = []
        store.onRecorded = { recorded.append($0.map(\.id)) }
        try await store.addBatch([Self.expense(id: "a"), Self.expense(id: "b")])
        try await store.addBatch([Self.expense(id: "a"), Self.expense(id: "b")])
        #expect(recorded == [["a", "b"]])
    }

    @Test("A new recurring series reaches onSeriesCreated")
    func createSeriesCallsOnSeriesCreated() async throws {
        let store = Self.makeStore()
        store.addCategory(CustomCategory(id: "subs", name: "Подписки", colorHex: "#8b5cf6", type: .expense))
        var created: [String] = []
        store.onSeriesCreated = { created.append($0.id) }
        let series = RecurringSeries(
            id: "s1", amount: 4990, currency: "KZT", category: "Подписки", description: "Music",
            frequency: .monthly, startDate: "2026-11-06"
        )
        try await store.createSeries(series)
        #expect(created == ["s1"])
    }

    @Test("A tapped reminder's stash is taken once, by whoever comes first")
    func launchQuickAddTakenOnce() {
        AppCoordinator.pendingQuickAddOnLaunch = AppCoordinator.QuickAdd(category: nil)
        #expect(AppCoordinator.takeLaunchQuickAdd() == AppCoordinator.QuickAdd(category: nil))
        #expect(AppCoordinator.takeLaunchQuickAdd() == nil)
    }

    @Test("The screenshot demo answers Ten's offer, so Home's first frame has no reminder card")
    func screenshotDemoHidesOffer() {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        ScreenshotDemoMode.writeSetupCardOverrides(to: defaults)
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, defaults: defaults))
    }
}
