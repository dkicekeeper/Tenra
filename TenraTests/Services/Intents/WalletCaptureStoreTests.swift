//
//  WalletCaptureStoreTests.swift
//  TenraTests
//
//  Pins the journal of Apple Pay payments: the double-fire guard, the To review
//  list, the queue of payments waiting for an exchange rate, the 90-day
//  retention, and what confirming a captured payment teaches the merchant and
//  card memories.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct WalletCaptureStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "wallet.captures.\(UUID().uuidString)")!
    }

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func payment(
        _ amount: Double = 3_500,
        merchant: String = "GREENMART CASH&CARRY 123",
        card: String = "Gold Card",
        currency: String? = nil,
        at offset: TimeInterval = 0
    ) -> WalletPayment {
        WalletPayment(
            id: UUID().uuidString,
            amount: amount,
            currencyCode: currency,
            merchant: merchant,
            card: card,
            accountId: nil,
            date: start.addingTimeInterval(offset)
        )
    }

    // MARK: - Duplicates

    @Test("The same payment within 90 seconds is a terminal firing twice")
    func duplicateWithinWindow() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-1", payment: payment(), guesses: [], now: start)

        #expect(store.isDuplicate(payment(merchant: "Greenmart Cash&Carry 456", card: " gold  card", at: 60)))
    }

    @Test("A later payment, or a different amount, card or currency, is a new payment")
    func notDuplicate() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-1", payment: payment(), guesses: [], now: start)

        #expect(!store.isDuplicate(payment(at: 91)))
        #expect(!store.isDuplicate(payment(3_600, at: 10)))
        #expect(!store.isDuplicate(payment(card: "Black Card", at: 10)))
        #expect(!store.isDuplicate(payment(currency: "USD", at: 10)))
        #expect(!store.isDuplicate(payment(merchant: "Corner Bakery", at: 10)))
    }

    @Test("A queued payment counts for the guard too")
    func pendingCountsAsDuplicate() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.enqueue(payment(12.5, currency: "EUR"))

        #expect(store.isDuplicate(payment(12.5, currency: "EUR", at: 30)))
    }

    // MARK: - To review

    @Test("Only payments with a guess are listed, newest first, until reviewed")
    func toReview() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-old", payment: payment(at: 0), guesses: [.category], now: start)
        store.record(transactionId: "tx-sure", payment: payment(at: 100), guesses: [], now: start)
        store.record(transactionId: "tx-new", payment: payment(at: 200), guesses: [.account, .category], now: start)

        #expect(store.toReview.map(\.id) == ["tx-new", "tx-old"])

        store.markReviewed(transactionId: "tx-new")
        #expect(store.toReview.map(\.id) == ["tx-old"])
        #expect(store.capture(forTransactionId: "tx-new")?.isReviewed == true)
    }

    @Test("Captures older than 90 days are dropped on the next record")
    func retention() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-old", payment: payment(), guesses: [.category], now: start)

        let later = start.addingTimeInterval(WalletCaptureStore.retention + 60)
        store.record(transactionId: "tx-new", payment: payment(at: WalletCaptureStore.retention + 60), guesses: [], now: later)

        #expect(store.capture(forTransactionId: "tx-old") == nil)
        #expect(store.capture(forTransactionId: "tx-new") != nil)
    }

    @Test("Captures of deleted transactions are dropped")
    func removeDeleted() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-1", payment: payment(), guesses: [.category], now: start)
        store.record(transactionId: "tx-2", payment: payment(at: 100), guesses: [.category], now: start)

        store.removeCaptures(notIn: ["tx-2"])

        #expect(store.capture(forTransactionId: "tx-1") == nil)
        #expect(store.toReview.map(\.id) == ["tx-2"])
    }

    // MARK: - Pending

    @Test("A payment is queued once and leaves the queue by id")
    func pendingQueue() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        let first = payment(12.5, currency: "EUR")
        let second = payment(8, currency: "USD", at: 300)

        store.enqueue(first)
        store.enqueue(first)
        store.enqueue(second)
        #expect(store.pending.map(\.id) == [first.id, second.id])

        store.removePending(id: first.id)
        #expect(store.pending.map(\.id) == [second.id])
    }

    @Test("Captures and the queue survive a relaunch")
    func persistence() {
        let defaults = makeDefaults()
        let queued = payment(12.5, currency: "EUR")
        do {
            let store = WalletCaptureStore(defaults: defaults)
            store.record(transactionId: "tx-1", payment: payment(), guesses: [.account], now: start)
            store.enqueue(queued)
        }

        let reloaded = WalletCaptureStore(defaults: defaults)
        #expect(reloaded.capture(forTransactionId: "tx-1")?.guesses == Set([WalletCaptureStore.Guess.account]))
        #expect(reloaded.pending == [queued])
    }

    // MARK: - Confirming a captured payment

    private let groceries = CustomCategory(id: "cat-groceries", name: "Продукты", colorHex: "#00AA00", type: .expense)

    private func transaction(_ id: String, category: String, accountId: String?) -> Transaction {
        Transaction(
            id: id,
            date: "2026-10-19",
            description: "GREENMART CASH&CARRY 123",
            amount: 3_500,
            currency: "KZT",
            type: .expense,
            category: category,
            accountId: accountId
        )
    }

    @Test("Confirming teaches the merchant's category and the card's account")
    func confirmTeachesMemories() {
        let defaults = makeDefaults()
        let captures = WalletCaptureStore(defaults: defaults)
        let merchants = MerchantCategoryMemory(defaults: defaults)
        let cards = CardAccountMemory(defaults: defaults)
        captures.record(transactionId: "tx-1", payment: payment(), guesses: [.category, .account], now: start)

        WalletPaymentRecorder.confirm(
            transaction("tx-1", category: "Продукты", accountId: "a2"),
            subcategoryIds: ["sub-1"],
            categories: [groceries],
            captures: captures,
            merchants: merchants,
            cards: cards
        )

        #expect(merchants.category(forMerchant: "GREENMART CASH&CARRY 456", in: [groceries])?.id == groceries.id)
        #expect(merchants.subcategoryIds(forMerchant: "Greenmart Cash&Carry") == ["sub-1"])
        #expect(cards.accountId(forCard: "gold card") == "a2")
        #expect(captures.toReview.isEmpty)
    }

    @Test("A transaction the Wallet action did not record teaches nothing")
    func confirmIgnoresOtherTransactions() {
        let defaults = makeDefaults()
        let captures = WalletCaptureStore(defaults: defaults)
        let merchants = MerchantCategoryMemory(defaults: defaults)
        let cards = CardAccountMemory(defaults: defaults)

        WalletPaymentRecorder.confirm(
            transaction("tx-manual", category: "Продукты", accountId: "a2"),
            subcategoryIds: [],
            categories: [groceries],
            captures: captures,
            merchants: merchants,
            cards: cards
        )

        #expect(merchants.merchants.isEmpty)
        #expect(cards.accountId(forCard: "Gold Card") == nil)
    }
}
