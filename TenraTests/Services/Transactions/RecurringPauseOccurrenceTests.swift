//
//  RecurringPauseOccurrenceTests.swift
//  TenraTests
//
//  M-5: pauseSubscription must prune future OCCURRENCES (not just future
//  transactions). Before the fix, pause deleted the future tx but left the
//  matching occurrence orphaned in RecurringStore, so resume could skip a
//  period or leave a gap (the generator's "should I generate?" guard sees an
//  occurrence that no longer has a backing transaction).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct RecurringPauseOccurrenceTests {

    // MARK: - Harness

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: balance,
            recurringStore: recurring
        )
        // validateSeries requires the category to exist by name and the account by id.
        store.categories = [
            CustomCategory(name: "Entertainment", iconSource: .sfSymbol("tv"),
                           colorHex: "#FF0000", type: .expense)
        ]
        store.accounts = [
            Account(id: "a1", name: "Main", currency: "USD", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        return store
    }

    private static func df() -> DateFormatter { DateFormatters.dateFormatter }

    /// Start date N months in the past so generateUpToNextFuture backfills past
    /// occurrences AND creates exactly one FUTURE occurrence.
    private static func startDate(monthsAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date())!
        return df().string(from: date)
    }

    private static func futureOccurrences(_ store: TransactionStore, seriesId: String) -> [RecurringOccurrence] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.recurringOccurrences.filter { occ in
            guard occ.seriesId == seriesId else { return false }
            guard let date = Self.df().date(from: occ.occurrenceDate) else { return false }
            return date > today
        }
    }

    private static func futureTransactions(_ store: TransactionStore, seriesId: String) -> [Transaction] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.transactions.filter { tx in
            guard tx.recurringSeriesId == seriesId else { return false }
            guard let date = Self.df().date(from: tx.date) else { return false }
            return date > today
        }
    }

    // MARK: - M-5

    @Test("pauseSubscription prunes the future occurrence, not just the future tx")
    func pausePrunesFutureOccurrence() async throws {
        let store = Self.makeStore()
        let series = RecurringSeries(
            id: "sub-1",
            isActive: true,
            amount: Decimal(10),
            currency: "USD",
            category: "Entertainment",
            description: "Netflix",
            accountId: "a1",
            frequency: .monthly,
            startDate: Self.startDate(monthsAgo: 2),
            kind: .subscription,
            status: .active
        )

        try await store.createSeries(series)

        // Sanity: creation generated a future occurrence + a future tx.
        #expect(!Self.futureOccurrences(store, seriesId: "sub-1").isEmpty,
                "createSeries should generate a future occurrence")
        #expect(!Self.futureTransactions(store, seriesId: "sub-1").isEmpty,
                "createSeries should generate a future tx")

        try await store.pauseSubscription(id: "sub-1")

        // After pause: no orphan future occurrence and no future tx.
        #expect(Self.futureTransactions(store, seriesId: "sub-1").isEmpty,
                "pause must delete future transactions")
        #expect(Self.futureOccurrences(store, seriesId: "sub-1").isEmpty,
                "pause must prune future occurrences (M-5)")
    }

    @Test("resume after pause regenerates exactly one correct future occurrence")
    func resumeAfterPauseRegeneratesNext() async throws {
        let store = Self.makeStore()
        let series = RecurringSeries(
            id: "sub-2",
            isActive: true,
            amount: Decimal(10),
            currency: "USD",
            category: "Entertainment",
            description: "Spotify",
            accountId: "a1",
            frequency: .monthly,
            startDate: Self.startDate(monthsAgo: 2),
            kind: .subscription,
            status: .active
        )

        try await store.createSeries(series)
        try await store.pauseSubscription(id: "sub-2")
        #expect(Self.futureOccurrences(store, seriesId: "sub-2").isEmpty)

        try await store.resumeSubscription(id: "sub-2")

        let futureOccs = Self.futureOccurrences(store, seriesId: "sub-2")
        #expect(futureOccs.count == 1,
                "resume should regenerate exactly one future occurrence, not skip/gap")

        // The regenerated occurrence must be a future date (the next period), and
        // there must be a matching future transaction for it.
        let futureTxs = Self.futureTransactions(store, seriesId: "sub-2")
        #expect(futureTxs.count == 1, "resume should create exactly one future tx")
    }
}
