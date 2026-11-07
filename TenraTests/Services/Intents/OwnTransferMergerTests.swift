//
//  OwnTransferMergerTests.swift
//  TenraTests
//
//  An expense and an income of two banks, recorded from their notifications, become one
//  transfer once the history is loaded; "Not a transfer" puts them back, never to be paired
//  again; confirming remembers both names as the person's own. Invented values.
//  docs/domains/intents.md §7.3.
//

import Testing
import Foundation
@testable import Tenra

// Serialized: a pass runs one at a time (a static guard), so two tests of the suite at once
// would see each other's pass in flight.
@Suite(.serialized)
@MainActor
struct OwnTransferMergerTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.categories = [
            CustomCategory(name: "Other", iconSource: .sfSymbol("tag"), colorHex: "#22c55e", type: .expense),
            CustomCategory(name: "Top-ups", iconSource: .sfSymbol("arrow.down"), colorHex: "#22c55e", type: .income)
        ]
        store.accounts = [
            Account(id: "freedom", name: "Freedom", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "kaspi", name: "Kaspi Gold", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        store.hasCompletedInitialLoad = true
        return store
    }

    private static let today = DateFormatters.dateFormatter.string(from: Date())

    private static func payment(_ id: String, incoming: Bool, app: String, party: String) -> WalletPayment {
        WalletPayment(
            id: id, amount: 100_000, currencyCode: "KZT", merchant: party, card: app,
            accountId: nil, date: Date(), bankApp: app, isIncome: incoming, isTransferLike: true
        )
    }

    /// Both sides recorded, the pair queued as the intent queues it.
    private static func recordBothSides(
        _ store: TransactionStore,
        _ captures: WalletCaptureStore,
        isConfident: Bool,
        sentGuesses: Set<WalletCaptureStore.Guess> = [.category]
    ) async throws -> (Transaction, Transaction) {
        let sent = try await store.add(Transaction(
            id: "out", date: today, description: "Иван П.", amount: 100_000, currency: "KZT",
            type: .expense, category: "Other", accountId: "freedom"
        ))
        let received = try await store.add(Transaction(
            id: "in", date: today, description: "Мария С.", amount: 100_000, currency: "KZT",
            type: .income, category: "Top-ups", accountId: "kaspi"
        ))
        captures.record(transactionId: "out", payment: payment("p-out", incoming: false, app: "Freedom", party: "Иван П."),
                        guesses: sentGuesses, accountId: "freedom")
        captures.record(transactionId: "in", payment: payment("p-in", incoming: true, app: "Kaspi.kz", party: "Мария С."),
                        guesses: [.category], accountId: "kaspi")
        captures.addOwnTransferPair(OwnTransferPairing.Pair(outgoingId: "out", incomingId: "in", isConfident: isConfident))
        return (sent, received)
    }

    @Test("The pair becomes one transfer from the expense's account to the income's; a guess waits in To review")
    func mergesIntoATransfer() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        _ = try await Self.recordBothSides(store, captures, isConfident: false)

        await OwnTransferMerger.mergePending(store: store, captures: captures)

        #expect(store.transactionById["out"] == nil)
        #expect(store.transactionById["in"] == nil)
        let transfer = try #require(store.transactions.first { $0.type == .internalTransfer })
        #expect(transfer.accountId == "freedom")
        #expect(transfer.targetAccountId == "kaspi")
        #expect(transfer.amount == 100_000)
        #expect(transfer.targetAmount == 100_000)
        #expect(captures.ownTransferPairs.isEmpty)
        let capture = try #require(captures.capture(forTransactionId: transfer.id))
        #expect(capture.needsReview)
        #expect(capture.guesses == [.ownTransfer])
        #expect(captures.toReview.map(\.id) == [transfer.id])
    }

    @Test("A confident pair needs no review")
    func confidentPairIsQuiet() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        _ = try await Self.recordBothSides(store, captures, isConfident: true)

        await OwnTransferMerger.mergePending(store: store, captures: captures)

        #expect(captures.toReview.isEmpty)
        #expect(store.transactions.filter { $0.type == .internalTransfer }.count == 1)
    }

    @Test("Not a transfer: the expense and the income come back and are never paired again")
    func splitPutsThemBack() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        let (sent, received) = try await Self.recordBothSides(store, captures, isConfident: false)
        await OwnTransferMerger.mergePending(store: store, captures: captures)
        let transfer = try #require(store.transactions.first { $0.type == .internalTransfer })

        try await OwnTransferMerger.split(transferId: transfer.id, store: store, captures: captures)

        #expect(store.transactionById[transfer.id] == nil)
        #expect(store.transactionById["out"] == sent)
        #expect(store.transactionById["in"] == received)
        #expect(captures.capture(forTransactionId: "out")?.pairingDismissed == true)
        #expect(captures.capture(forTransactionId: "in")?.pairingDismissed == true)
        #expect(captures.unpairedBankSides(around: Date()).isEmpty)
        // Back with what Tenra had guessed for them: their categories wait in To review again.
        #expect(Set(captures.toReview.map(\.id)) == ["out", "in"])
    }

    @Test("Two passes at once (the intent and the foreground) move the money once")
    func reentrantPassesMergeOnce() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        _ = try await Self.recordBothSides(store, captures, isConfident: true)

        async let first: Void = OwnTransferMerger.mergePending(store: store, captures: captures)
        async let second: Void = OwnTransferMerger.mergePending(store: store, captures: captures)
        _ = await (first, second)

        #expect(store.transactions.filter { $0.type == .internalTransfer }.count == 1)
        #expect(store.transactions.count == 1)
    }

    @Test("A guessed account stays a guess on the transfer, and comes back with the sides")
    func accountGuessIsKept() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        _ = try await Self.recordBothSides(store, captures, isConfident: true, sentGuesses: [.account])
        await OwnTransferMerger.mergePending(store: store, captures: captures)
        let transfer = try #require(store.transactions.first { $0.type == .internalTransfer })
        #expect(captures.capture(forTransactionId: transfer.id)?.guesses == [.account])
        #expect(captures.toReview.map(\.id) == [transfer.id])

        try await OwnTransferMerger.split(transferId: transfer.id, store: store, captures: captures)
        #expect(captures.capture(forTransactionId: "out")?.guesses == [.account])
        #expect(captures.capture(forTransactionId: "out")?.needsReview == true)
        #expect(captures.capture(forTransactionId: "in")?.guesses == [.category])
    }

    @Test("A split that cannot put the sides back leaves the transfer as it was")
    func failedSplitKeepsTheTransfer() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        _ = try await Self.recordBothSides(store, captures, isConfident: false)
        await OwnTransferMerger.mergePending(store: store, captures: captures)
        let transfer = try #require(store.transactions.first { $0.type == .internalTransfer })
        // The income's category is gone since: the income cannot be saved again.
        store.categories.removeAll { $0.name == "Top-ups" }

        await #expect(throws: (any Error).self) {
            try await OwnTransferMerger.split(transferId: transfer.id, store: store, captures: captures)
        }
        #expect(store.transactionById[transfer.id] != nil)
        #expect(store.transactionById["out"] == nil)
        #expect(store.transactionById["in"] == nil)
        #expect(captures.capture(forTransactionId: transfer.id)?.ownTransfer != nil)
    }

    @Test("Confirming the transfer remembers both names as the person's own")
    func confirmRemembersNames() async throws {
        let store = Self.makeStore()
        let captures = WalletCaptureStore(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        _ = try await Self.recordBothSides(store, captures, isConfident: false)
        await OwnTransferMerger.mergePending(store: store, captures: captures)
        let transfer = try #require(store.transactions.first { $0.type == .internalTransfer })

        WalletPaymentRecorder.confirm(
            transfer,
            subcategoryIds: [],
            categories: store.categories,
            captures: captures,
            merchants: MerchantCategoryMemory(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!),
            cards: CardAccountMemory(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        )

        #expect(captures.toReview.isEmpty)
        #expect(captures.ownNames == ["иван п", "мария с"])
    }
}
