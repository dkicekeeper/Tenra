//
//  SubscriptionChargeLinkerTests.swift
//  TenraTests
//
//  A real subscription charge (a bank's notification, an expense entered by hand) linked to a
//  subscription merges into the planned charge of its period: one charge stays one
//  transaction. docs/domains/recurring.md §Real charges.
//

import Testing
import Foundation
@testable import Tenra

// Serialized: a pass runs one at a time (a static guard), so two tests of the suite at once
// would see each other's pass in flight.
@Suite(.serialized)
@MainActor
struct SubscriptionChargeLinkerTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.categories = [
            CustomCategory(name: "Subscriptions", iconSource: .sfSymbol("repeat"), colorHex: "#22c55e", type: .expense),
            CustomCategory(name: "Other", iconSource: .sfSymbol("tag"), colorHex: "#22c55e", type: .expense)
        ]
        store.accounts = [
            Account(id: "a1", name: "Kaspi", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "a2", name: "Freedom", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        return store
    }

    private static func day(_ offset: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
    }

    /// A monthly subscription whose planned charge is two days ahead.
    private static func subscription(_ store: TransactionStore) async throws -> (RecurringSeries, Transaction) {
        let series = RecurringSeries(
            amount: 2_990, currency: "KZT", category: "Subscriptions", description: "Яндекс Плюс",
            accountId: "a1", frequency: .monthly, startDate: day(2), kind: .subscription
        )
        try await store.createSeries(series)
        let planned = try #require(store.transactions.first { $0.recurringSeriesId == series.id })
        return (series, planned)
    }

    @Test("A charge picked by hand merges into the planned charge: one transaction with the bank's amount, date and account")
    func mergesIntoThePlannedCharge() async throws {
        let store = Self.makeStore()
        let (series, planned) = try await Self.subscription(store)
        let bank = try await store.add(Transaction(
            id: "bank", date: Self.day(0), description: "YANDEX*PLUS", amount: 3_190, currency: "KZT",
            type: .expense, category: "Other", accountId: "a2"
        ))
        let captures = WalletCaptureStore(defaults: Self.defaults())
        let memory = SubscriptionMerchantMemory(defaults: Self.defaults())

        let outcome = try await SubscriptionChargeLinker.link(bank, to: series, store: store, captures: captures, memory: memory)

        #expect(outcome == .merged(occurrenceId: planned.id))
        #expect(store.transactionById["bank"] == nil)
        let merged = try #require(store.transactionById[planned.id])
        #expect(merged.amount == 3_190)
        #expect(merged.date == Self.day(0))
        #expect(merged.accountId == "a2")
        #expect(merged.description == "Яндекс Плюс")
        #expect(merged.recurringSeriesId == series.id)
        #expect(store.transactions.filter { $0.recurringSeriesId == series.id }.count == 1)
        #expect(captures.isMatched(occurrenceId: planned.id))
        #expect(memory.seriesId(forMerchant: "YANDEX*PLUS") == series.id)
    }

    @Test("A captured charge keeps its capture under the planned charge: the other source's report stays a duplicate")
    func captureMovesToThePlannedCharge() async throws {
        let store = Self.makeStore()
        let (series, planned) = try await Self.subscription(store)
        let bank = try await store.add(Transaction(
            id: "bank", date: Self.day(0), description: "YANDEX*PLUS", amount: 3_190, currency: "KZT",
            type: .expense, category: "Other", accountId: "a2"
        ))
        let captures = WalletCaptureStore(defaults: Self.defaults())
        let payment = WalletPayment(
            id: "p1", amount: 3_190, currencyCode: "KZT", merchant: "YANDEX*PLUS", card: "Freedom",
            accountId: nil, date: Date(), bankApp: "Freedom"
        )
        captures.record(transactionId: "bank", payment: payment, guesses: [.category], subscriptionSuggestion: series.id)

        try await SubscriptionChargeLinker.link(
            bank, to: series, store: store, captures: captures,
            memory: SubscriptionMerchantMemory(defaults: Self.defaults())
        )

        #expect(captures.capture(forTransactionId: "bank") == nil)
        #expect(captures.capture(forTransactionId: planned.id)?.payment == payment)
        #expect(captures.toReview.isEmpty)
        let applePay = WalletPayment(id: "p2", amount: 3_190, currencyCode: "KZT", merchant: "YANDEX", card: "Apple Card",
                                     accountId: nil, date: Date().addingTimeInterval(60))
        #expect(captures.isDuplicate(applePay))
    }

    @Test("A queued charge whose planned charge is gone is saved as an expense of its own, never lost")
    func pendingMergeWithoutItsPlannedChargeIsSaved() async throws {
        let store = Self.makeStore()
        store.hasCompletedInitialLoad = true
        let captures = WalletCaptureStore(defaults: Self.defaults())
        captures.enqueueChargeMerge(WalletCaptureStore.ChargeMerge(
            occurrenceId: "gone", amount: 3_050, currency: "KZT", convertedAmount: nil,
            accountId: "a2", date: Self.day(0), categoryName: "Other", note: "YANDEX*PLUS"
        ))

        await SubscriptionChargeLinker.applyPending(store: store, captures: captures)

        let saved = try #require(store.transactions.first { $0.description == "YANDEX*PLUS" })
        #expect(saved.amount == 3_050)
        #expect(saved.accountId == "a2")
        #expect(captures.chargeMerges.isEmpty)
    }

    @Test("With no planned charge near, the expense is linked to the subscription as it is")
    func linksWhenNoPlannedChargeIsNear() async throws {
        let store = Self.makeStore()
        let (series, planned) = try await Self.subscription(store)
        let old = try await store.add(Transaction(
            id: "old", date: Self.day(-40), description: "YANDEX*PLUS", amount: 2_990, currency: "KZT",
            type: .expense, category: "Other", accountId: "a1"
        ))

        let outcome = try await SubscriptionChargeLinker.link(
            old, to: series, store: store,
            captures: WalletCaptureStore(defaults: Self.defaults()),
            memory: SubscriptionMerchantMemory(defaults: Self.defaults())
        )

        #expect(outcome == .linked)
        #expect(store.transactionById["old"]?.recurringSeriesId == series.id)
        #expect(store.transactionById[planned.id]?.amount == 2_990)
    }

    @Test("A charge an intent matched before the full load merges once the history is loaded")
    func pendingMergeAppliesAfterTheLoad() async throws {
        let store = Self.makeStore()
        let (_, planned) = try await Self.subscription(store)
        let captures = WalletCaptureStore(defaults: Self.defaults())
        captures.enqueueChargeMerge(WalletCaptureStore.ChargeMerge(
            occurrenceId: planned.id, amount: 3_050, currency: "KZT", convertedAmount: nil,
            accountId: "a2", date: Self.day(0)
        ))

        await SubscriptionChargeLinker.applyPending(store: store, captures: captures)
        #expect(store.transactionById[planned.id]?.amount == 2_990, "nothing before the full load")
        #expect(captures.chargeMerges.count == 1)

        store.hasCompletedInitialLoad = true
        await SubscriptionChargeLinker.applyPending(store: store, captures: captures)
        #expect(store.transactionById[planned.id]?.amount == 3_050)
        #expect(store.transactionById[planned.id]?.accountId == "a2")
        #expect(store.transactionById[planned.id]?.date == Self.day(0))
        #expect(captures.chargeMerges.isEmpty)
    }
}
