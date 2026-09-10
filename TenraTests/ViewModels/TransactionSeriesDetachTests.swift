//
//  TransactionSeriesDetachTests.swift
//  TenraTests
//
//  `TransactionStore.update` used to reject ANY edit that cleared
//  `recurringSeriesId`, including edits that never intended to touch the series:
//
//  - a transaction whose series no longer exists (dangling link) could never be
//    edited again — every save threw `cannotRemoveRecurring`, which is how the
//    "cannot remove recurring series" error surfaced when editing an auto-posted
//    deposit-interest transaction (its edit screen hides the recurring control,
//    so the form always reports `.never`);
//  - the edit screen's explicit "Never" option produced the same dead end for
//    regular income/expense transactions.
//
//  The guard now protects only what it can protect: detaching from a series that
//  actually exists, and only when the caller did not explicitly ask to detach.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionSeriesDetachTests {

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

    private static func today() -> String {
        DateFormatters.dateFormatter.string(from: Date())
    }

    private static func tx(
        id: String,
        amount: Double,
        type: TransactionType = .expense,
        category: String = "Entertainment",
        seriesId: String?
    ) -> Transaction {
        Transaction(
            id: id,
            date: today(),
            description: "",
            amount: amount,
            currency: "USD",
            type: type,
            category: category,
            accountId: "a1",
            recurringSeriesId: seriesId
        )
    }

    /// Creates a real series in the store and returns its id.
    private static func makeLiveSeries(_ store: TransactionStore) async throws -> String {
        let series = RecurringSeries(
            amount: 10,
            currency: "USD",
            category: "Entertainment",
            subcategory: nil,
            description: "Netflix",
            accountId: "a1",
            targetAccountId: nil,
            frequency: .monthly,
            startDate: today()
        )
        try await store.createSeries(series)
        return series.id
    }

    // MARK: - Dangling series link

    @Test("A transaction pointing at a non-existent series can be edited")
    func editingTransactionWithDanglingSeriesLinkSucceeds() async throws {
        let store = Self.makeStore()

        // Deposit-interest accrual carrying a link to a series that is gone.
        let original = Self.tx(
            id: "di_dangling",
            amount: 100,
            type: .depositInterestAccrual,
            category: "Interest",
            seriesId: "series-that-no-longer-exists"
        )
        _ = try await store.add(original)

        // The edit screen for this type hides the recurring control, so it saves
        // with recurringSeriesId == nil.
        let edited = Self.tx(
            id: "di_dangling",
            amount: 250,
            type: .depositInterestAccrual,
            category: "Interest",
            seriesId: nil
        )

        try await store.update(edited)

        #expect(store.transactionById["di_dangling"]?.amount == 250)
        #expect(store.transactionById["di_dangling"]?.recurringSeriesId == nil)
    }

    // MARK: - Live series link

    @Test("Clearing a live series link without opting in is still rejected")
    func accidentalDetachFromLiveSeriesIsRejected() async throws {
        let store = Self.makeStore()
        let seriesId = try await Self.makeLiveSeries(store)

        let original = Self.tx(id: "t1", amount: 10, seriesId: seriesId)
        _ = try await store.add(original)

        let edited = Self.tx(id: "t1", amount: 20, seriesId: nil)

        var thrown: TransactionStoreError?
        do {
            try await store.update(edited)
        } catch let error as TransactionStoreError {
            thrown = error
        }
        guard case .cannotRemoveRecurring = thrown else {
            Issue.record("expected .cannotRemoveRecurring, got \(String(describing: thrown))")
            return
        }
        #expect(store.transactionById["t1"]?.recurringSeriesId == seriesId)
    }

    @Test("Explicit detach from a live series is allowed")
    func explicitDetachFromLiveSeriesSucceeds() async throws {
        let store = Self.makeStore()
        let seriesId = try await Self.makeLiveSeries(store)

        let original = Self.tx(id: "t2", amount: 10, seriesId: seriesId)
        _ = try await store.add(original)

        let edited = Self.tx(id: "t2", amount: 20, seriesId: nil)

        try await store.update(edited, allowSeriesDetach: true)

        #expect(store.transactionById["t2"]?.recurringSeriesId == nil)
        #expect(store.transactionById["t2"]?.amount == 20)
    }
}
