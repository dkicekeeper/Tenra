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

    private func bankPayment(
        _ amount: Double = 3_500,
        merchant: String = "Greenmart",
        isIncome: Bool = false,
        at offset: TimeInterval
    ) -> WalletPayment {
        WalletPayment(
            id: UUID().uuidString,
            amount: amount,
            currencyCode: "KZT",
            merchant: merchant,
            card: "Bank •• 1234",
            accountId: nil,
            date: start.addingTimeInterval(offset),
            bankApp: "Bank",
            isIncome: isIncome
        )
    }

    @Test("Apple Pay and the bank's notification of the same payment are one payment, either order")
    func crossSourceDuplicate() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-1", payment: payment(currency: "KZT"), guesses: [], now: start)

        #expect(store.isDuplicate(bankPayment(at: 120)))
        #expect(!store.isDuplicate(bankPayment(at: WalletCaptureStore.crossSourceWindow + 1)))
        #expect(!store.isDuplicate(bankPayment(3_600, at: 120)))
        #expect(!store.isDuplicate(bankPayment(isIncome: true, at: 120)))

        let other = WalletCaptureStore(defaults: makeDefaults())
        other.record(transactionId: "tx-2", payment: bankPayment(at: 0), guesses: [], now: start)
        #expect(other.isDuplicate(payment(currency: "KZT", at: 60)))
    }

    @Test("Two notifications of the same bank are the same payment only within the repeat window")
    func bankRepeat() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-1", payment: bankPayment(at: 0), guesses: [], now: start)

        #expect(store.isDuplicate(bankPayment(at: 60)))
        #expect(!store.isDuplicate(bankPayment(at: 200)))
        #expect(!store.isDuplicate(bankPayment(merchant: "Иван П.", at: 60)))
    }

    @Test("A bank notification's merchants are never looked up online: they name people too")
    func bankMerchantsStayLocal() {
        let store = WalletCaptureStore(defaults: makeDefaults())
        store.record(transactionId: "tx-1", payment: payment(), guesses: [], now: start)
        store.record(transactionId: "tx-2", payment: bankPayment(merchant: "Иван П.", at: 600), guesses: [], now: start)

        #expect(store.merchants == ["GREENMART CASH&CARRY 123"])
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

    @Test("An edit teaches only what changed: a guessed account kept as it was stays a guess")
    func editTeachesChangesOnly() {
        let defaults = makeDefaults()
        let captures = WalletCaptureStore(defaults: defaults)
        let merchants = MerchantCategoryMemory(defaults: defaults)
        let cards = CardAccountMemory(defaults: defaults)
        captures.record(transactionId: "tx-1", payment: payment(), guesses: [.account], now: start)
        let before = transaction("tx-1", category: "Продукты", accountId: "a1")

        // Only the note changed.
        WalletPaymentRecorder.confirm(
            transaction("tx-1", category: "Продукты", accountId: "a1"),
            subcategoryIds: [],
            categories: [groceries],
            editedFrom: before,
            previousSubcategoryIds: [],
            captures: captures,
            merchants: merchants,
            cards: cards
        )
        #expect(cards.accountId(forCard: "gold card") == nil)
        #expect(merchants.merchants.isEmpty)
        #expect(captures.toReview.isEmpty)

        // The account changed: that is the card's account now.
        WalletPaymentRecorder.confirm(
            transaction("tx-1", category: "Продукты", accountId: "a2"),
            subcategoryIds: [],
            categories: [groceries],
            editedFrom: before,
            previousSubcategoryIds: [],
            captures: captures,
            merchants: merchants,
            cards: cards
        )
        #expect(cards.accountId(forCard: "gold card") == "a2")
    }

    @Test("A guessed category the user had not reviewed is confirmed by saving its edit")
    func editConfirmsUnreviewedCategoryGuess() {
        let defaults = makeDefaults()
        let captures = WalletCaptureStore(defaults: defaults)
        let merchants = MerchantCategoryMemory(defaults: defaults)
        let cards = CardAccountMemory(defaults: defaults)
        captures.record(transactionId: "tx-1", payment: payment(), guesses: [.category], now: start)
        let before = transaction("tx-1", category: "Продукты", accountId: "a1")

        WalletPaymentRecorder.confirm(
            before,
            subcategoryIds: [],
            categories: [groceries],
            editedFrom: before,
            previousSubcategoryIds: [],
            captures: captures,
            merchants: merchants,
            cards: cards
        )
        #expect(merchants.category(forMerchant: "GREENMART CASH&CARRY 1", in: [groceries])?.id == groceries.id)
        #expect(cards.accountId(forCard: "gold card") == nil)
    }

    @Test("A subscription charge taken for a payment stays taken after a relaunch")
    func matchedOccurrences() {
        let defaults = makeDefaults()
        do {
            let store = WalletCaptureStore(defaults: defaults)
            #expect(!store.isMatched(occurrenceId: "occ-1"))
            store.noteMatched(occurrenceId: "occ-1", now: start)
        }
        #expect(WalletCaptureStore(defaults: defaults).isMatched(occurrenceId: "occ-1"))
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
