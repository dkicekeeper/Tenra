//
//  WalletCaptureStore.swift
//  Tenra
//
//  The journal of Apple Pay payments LogWalletPaymentIntent recorded:
//
//  • captures: for each saved transaction, the payment as Wallet sent it (merchant,
//    card) and what Tenra had to guess (category, account). A capture with a guess
//    the user has not looked at yet is "To review". The merchant and card stay
//    attached after the review, so a later fix in the edit screen still teaches
//    MerchantCategoryMemory and CardAccountMemory.
//  • pending: payments in another currency that arrived with no exchange rate in
//    the cache and no network. Saved without a conversion, the balance would move by
//    the raw foreign amount (docs/domains/currency.md), so they wait here and are
//    recorded by the next payment or when the app comes to the front.
//
//  Both also answer "did this payment just arrive?": terminals sometimes fire the
//  automation twice for one tap, and a card payment at a terminal also makes the bank
//  send a notification (LogBankNotificationIntent records those through the same path).
//
//  Storage: a single Codable blob in `UserDefaults`, like MerchantCategoryMemory.
//  Captures are kept for 90 days, which bounds it by the number of Apple Pay
//  payments in a quarter.
//

import Foundation
import Observation

/// One payment as the Wallet automation delivered it, or one operation from a bank's
/// notification (`bankApp` set).
nonisolated struct WalletPayment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var amount: Double
    /// ISO 4217, uppercased; nil when the automation passed none (the account's currency).
    var currencyCode: String?
    /// "" when the automation passed none.
    var merchant: String
    /// The "Card or Pass" text; "" when the automation passed none.
    var card: String
    /// The account fixed in the automation, if any.
    var accountId: String?
    var date: Date
    /// The bank app whose notification this came from (LogBankNotificationIntent); nil for
    /// an Apple Pay payment.
    var bankApp: String? = nil
    /// Money in: a bank notification's top-up or incoming transfer. nil means an expense.
    var isIncome: Bool? = nil
    /// A bank notification's transfer or top-up, not a purchase (`BankNotification.isTransferLike`):
    /// one side of a transfer between the person's own banks may be it (OwnTransferPairing).
    /// nil for Apple Pay and for payments saved before it was kept.
    var isTransferLike: Bool? = nil

    var isExpense: Bool { isIncome != true }
}

@MainActor
@Observable
final class WalletCaptureStore {

    /// What Tenra decided on its own for a captured payment.
    enum Guess: String, Codable, Hashable {
        case category
        case account
        /// An expense and an income of two banks merged into a transfer on the amount and the
        /// time alone (OwnTransferPairing).
        case ownTransfer
    }

    /// A transfer merged from two bank notifications: what "Not a transfer" puts back.
    struct OwnTransferRecord: Codable, Equatable {
        /// The receiving side's notification (the capture's `payment` is the sending side's).
        let incoming: WalletPayment
        /// The expense and the income as they were saved.
        let originals: [Transaction]
        /// What Tenra guessed for each side, in the order of `originals`: put back with them.
        var guesses: [Set<Guess>]? = nil
    }

    struct Capture: Codable, Equatable, Identifiable {
        /// The saved transaction's id.
        let id: String
        let payment: WalletPayment
        var guesses: Set<Guess>
        var isReviewed: Bool
        /// The account it was saved on. nil in captures saved before it was kept.
        var accountId: String? = nil
        /// A subscription whose planned charge this payment may be (same amount and date, no
        /// shared word): To review asks. nil once answered.
        var subscriptionSuggestion: String? = nil
        /// Set on a transfer merged from two bank notifications.
        var ownTransfer: OwnTransferRecord? = nil
        /// The person said this payment is not half of a transfer: never paired again.
        var pairingDismissed: Bool? = nil

        var needsReview: Bool { (!isReviewed && !guesses.isEmpty) || subscriptionSuggestion != nil }
    }

    /// A real subscription charge an intent matched while the history was not loaded: the
    /// planned charge takes these values once it is (SubscriptionChargeLinker.applyPending).
    struct ChargeMerge: Codable, Equatable {
        let occurrenceId: String
        let amount: Double
        let currency: String
        let convertedAmount: Double?
        /// The account's currency and the amount in it when `currency` is another one.
        var targetCurrency: String? = nil
        var targetAmount: Double? = nil
        let accountId: String?
        /// "yyyy-MM-dd".
        let date: String
        /// What the payment is saved as when its planned charge is gone (deleted meanwhile).
        var categoryName: String = ""
        var note: String = ""
    }

    private struct Snapshot: Codable {
        var captures: [String: Capture]
        var pending: [WalletPayment]
        /// Subscription occurrences a payment was taken for (`[transaction id: when]`). nil in
        /// snapshots saved before it was kept.
        var matchedOccurrences: [String: Date]?
        /// When the first payment was ever recorded. nil in snapshots saved before it was kept.
        var firstCaptureAt: Date?
        /// Sides of transfers between own accounts waiting for their other side. nil in
        /// snapshots saved before it was kept.
        var transferSides: [OwnTransferMatcher.Side]?
        /// nil in snapshots saved before these were kept.
        var chargeMerges: [ChargeMerge]?
        var ownTransferPairs: [OwnTransferPairing.Pair]?
        var ownNames: [String]?
    }

    /// How much the automations record, for Diagnostics and the Home setup card. Local only.
    struct Activity: Equatable {
        var applePayLast7Days = 0
        var applePayLast30Days = 0
        var notificationsLast7Days = 0
        var notificationsLast30Days = 0
        var toReview = 0
        var pending = 0
        var lastCaptureAt: Date?
        var firstCaptureAt: Date?
    }

    static let shared = WalletCaptureStore()

    private static let storageKey = "intent.walletCaptures.v1"

    /// Two identical payments this close together are one tap fired twice.
    static let duplicateWindow: TimeInterval = 90
    /// An Apple Pay payment and a bank's notification of the same amount this close
    /// together are one payment, reported by both.
    static let crossSourceWindow: TimeInterval = 5 * 60
    /// Captures older than this are dropped: their review is long over.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    @ObservationIgnored private let defaults: UserDefaults
    /// `[transaction id: capture]`
    private var captures: [String: Capture]
    /// Oldest first.
    private(set) var pending: [WalletPayment]
    /// Occurrences of a recurring series already taken for an Apple Pay payment, so one
    /// charge of the series stands for one payment only. `[transaction id: when]`.
    private var matchedOccurrences: [String: Date]
    /// When an automation first recorded a payment; outlives the captures' 90 days, so
    /// "has auto-capture ever worked" stays answered.
    private(set) var firstCaptureAt: Date?
    /// One side of a transfer between own accounts per bank notification, until
    /// OwnTransferRecorder pairs it with the other bank's side (or it is two days old).
    private(set) var transferSides: [OwnTransferMatcher.Side]
    /// Real subscription charges waiting for the full load to merge into their planned charge.
    private(set) var chargeMerges: [ChargeMerge]
    /// An expense and an income of two banks waiting for the full load to become one transfer
    /// (OwnTransferMerger).
    private(set) var ownTransferPairs: [OwnTransferPairing.Pair]
    /// Counterparties the person confirmed as themselves (OwnTransferPairing.nameKey).
    private(set) var ownNames: Set<String>
    /// Set by a tap on a "check a payment" notification (WalletReviewNotifier): MainTabView
    /// presents the To review list. Not persisted.
    var isReviewRequested = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = Self.load(from: defaults)
        self.captures = snapshot.captures
        self.pending = snapshot.pending
        self.matchedOccurrences = snapshot.matchedOccurrences ?? [:]
        // Snapshots from before the field: the oldest kept capture is the best answer.
        self.firstCaptureAt = snapshot.firstCaptureAt ?? snapshot.captures.values.map(\.payment.date).min()
        self.transferSides = snapshot.transferSides ?? []
        self.chargeMerges = snapshot.chargeMerges ?? []
        self.ownTransferPairs = snapshot.ownTransferPairs ?? []
        self.ownNames = Set(snapshot.ownNames ?? [])
    }

    // MARK: - Transfers between own accounts

    func enqueueTransferSide(_ side: OwnTransferMatcher.Side) {
        guard !transferSides.contains(where: { $0.id == side.id }) else { return }
        transferSides.append(side)
        persist()
    }

    /// What OwnTransferRecorder left waiting.
    func setTransferSides(_ sides: [OwnTransferMatcher.Side]) {
        guard sides != transferSides else { return }
        transferSides = sides
        persist()
    }

    // MARK: - Captures

    func capture(forTransactionId id: String) -> Capture? {
        captures[id]
    }

    /// Captures with a guess the user has not looked at yet, newest first.
    var toReview: [Capture] {
        captures.values
            .filter(\.needsReview)
            .sorted { lhs, rhs in
                lhs.payment.date != rhs.payment.date ? lhs.payment.date > rhs.payment.date : lhs.id < rhs.id
            }
    }

    /// Whether a payment was saved: a queued one that a run ended before taking off the queue.
    func isRecorded(paymentId: String) -> Bool {
        captures.values.contains { $0.payment.id == paymentId }
    }

    /// The transactions the Wallet action saved, while their captures are kept (90 days).
    var transactionIds: [String] { Array(captures.keys) }

    /// The merchants of the kept Apple Pay captures, as Wallet wrote them, one per merchant.
    /// Not a bank notification's: those name people too (a transfer), and these merchants
    /// are looked up online (MerchantLogoResolver).
    var merchants: [String] {
        var seen = Set<String>()
        return captures.values
            .filter { $0.payment.bankApp == nil }
            .map(\.payment.merchant)
            .filter { !$0.isEmpty && seen.insert(CategorySuggestionService.normalizedMerchant($0)).inserted }
    }

    func record(
        transactionId: String,
        payment: WalletPayment,
        guesses: Set<Guess>,
        accountId: String? = nil,
        subscriptionSuggestion: String? = nil,
        now: Date = Date()
    ) {
        insert(Capture(
            id: transactionId,
            payment: payment,
            guesses: guesses,
            isReviewed: false,
            accountId: accountId,
            subscriptionSuggestion: subscriptionSuggestion
        ), now: now)
    }

    /// Keeps a capture as it is given: a merged transfer, a side put back by "Not a transfer".
    func insert(_ capture: Capture, now: Date = Date()) {
        guard !capture.id.isEmpty else { return }
        captures = captures.filter { now.timeIntervalSince($0.value.payment.date) <= Self.retention }
        captures[capture.id] = capture
        if firstCaptureAt == nil { firstCaptureAt = now }
        persist()
    }

    func removeCapture(transactionId: String) {
        guard captures.removeValue(forKey: transactionId) != nil else { return }
        persist()
    }

    /// The suggested subscription was answered: merged, or not this one.
    func clearSubscriptionSuggestion(transactionId: String) {
        guard var capture = captures[transactionId], capture.subscriptionSuggestion != nil else { return }
        capture.subscriptionSuggestion = nil
        captures[transactionId] = capture
        persist()
    }

    /// Whether the Wallet or a bank notification automation ever recorded a payment.
    var hasEverCaptured: Bool { firstCaptureAt != nil }

    /// Counts of the kept captures (90 days) by source and window.
    func activity(now: Date = Date()) -> Activity {
        var activity = Activity(
            toReview: captures.values.filter(\.needsReview).count,
            pending: pending.count,
            lastCaptureAt: captures.values.map(\.payment.date).max(),
            firstCaptureAt: firstCaptureAt
        )
        for capture in captures.values {
            let age = now.timeIntervalSince(capture.payment.date)
            guard age <= 30 * 86_400 else { continue }
            let isWeek = age <= 7 * 86_400
            if capture.payment.bankApp == nil {
                activity.applePayLast30Days += 1
                if isWeek { activity.applePayLast7Days += 1 }
            } else {
                activity.notificationsLast30Days += 1
                if isWeek { activity.notificationsLast7Days += 1 }
            }
        }
        return activity
    }

    /// The user looked at the transaction: in the edit screen, or "Correct" in the list.
    func markReviewed(transactionId: String) {
        guard var capture = captures[transactionId], !capture.isReviewed else { return }
        capture.isReviewed = true
        captures[transactionId] = capture
        persist()
    }

    /// Drops captures whose transaction no longer exists (deleted in the app).
    func removeCaptures(notIn transactionIds: Set<String>) {
        let kept = captures.filter { transactionIds.contains($0.key) }
        guard kept.count != captures.count else { return }
        captures = kept
        persist()
    }

    // MARK: - Subscription occurrences

    func isMatched(occurrenceId: String) -> Bool {
        matchedOccurrences[occurrenceId] != nil
    }

    /// A payment was taken for this occurrence: later payments must not be.
    func noteMatched(occurrenceId: String, now: Date = Date()) {
        matchedOccurrences = matchedOccurrences.filter { now.timeIntervalSince($0.value) <= Self.retention }
        matchedOccurrences[occurrenceId] = now
        persist()
    }

    // MARK: - Real subscription charges

    func enqueueChargeMerge(_ merge: ChargeMerge) {
        chargeMerges.removeAll { $0.occurrenceId == merge.occurrenceId }
        chargeMerges.append(merge)
        persist()
    }

    func removeChargeMerges(occurrenceIds: Set<String>) {
        let kept = chargeMerges.filter { !occurrenceIds.contains($0.occurrenceId) }
        guard kept.count != chargeMerges.count else { return }
        chargeMerges = kept
        persist()
    }

    // MARK: - Transfers between own banks, without the bank's word

    /// The recorded bank notifications a new one may pair with: transfers and top-ups saved
    /// within `OwnTransferMatcher.window` of `date`, not merged, not put back by the person and
    /// not already waiting in a pair.
    func unpairedBankSides(around date: Date) -> [OwnTransferPairing.Side] {
        let waiting = Set(ownTransferPairs.flatMap { [$0.outgoingId, $0.incomingId] })
        return captures.values.compactMap { capture in
            guard let accountId = capture.accountId,
                  capture.payment.bankApp != nil,
                  capture.payment.isTransferLike == true,
                  capture.ownTransfer == nil,
                  capture.pairingDismissed != true,
                  !waiting.contains(capture.id),
                  abs(capture.payment.date.timeIntervalSince(date)) <= OwnTransferMatcher.window
            else { return nil }
            return OwnTransferPairing.Side(transactionId: capture.id, payment: capture.payment, accountId: accountId)
        }
    }

    func addOwnTransferPair(_ pair: OwnTransferPairing.Pair) {
        guard !ownTransferPairs.contains(where: {
            $0.outgoingId == pair.outgoingId || $0.incomingId == pair.incomingId
        }) else { return }
        ownTransferPairs.append(pair)
        persist()
    }

    func removeOwnTransferPair(_ pair: OwnTransferPairing.Pair) {
        guard ownTransferPairs.contains(pair) else { return }
        ownTransferPairs.removeAll { $0 == pair }
        persist()
    }

    /// The person confirmed a merged transfer: its names are theirs.
    func rememberOwnNames(_ counterparties: [String]) {
        let keys = counterparties.compactMap(OwnTransferPairing.nameKey)
        guard !Set(keys).isSubset(of: ownNames) else { return }
        ownNames.formUnion(keys)
        persist()
    }

    // MARK: - Pending

    func enqueue(_ payment: WalletPayment) {
        guard !pending.contains(where: { $0.id == payment.id }) else { return }
        pending.append(payment)
        persist()
    }

    func removePending(id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index)
        persist()
    }

    // MARK: - Duplicates

    /// True when the same payment (amount, currency, merchant, card) was recorded or
    /// queued within `duplicateWindow`, or the other source (Apple Pay, a bank's
    /// notification) reported an expense of the same amount within `crossSourceWindow`.
    func isDuplicate(_ payment: WalletPayment) -> Bool {
        let key = Self.duplicateKey(payment)
        let recent = captures.values.map(\.payment) + captures.values.compactMap(\.ownTransfer?.incoming) + pending
        return recent.contains { other in
            guard other.id != payment.id, abs(other.amount - payment.amount) < 0.005 else { return false }
            let gap = abs(other.date.timeIntervalSince(payment.date))
            if gap <= Self.duplicateWindow, Self.duplicateKey(other) == key { return true }
            return gap <= Self.crossSourceWindow
                && (other.bankApp == nil) != (payment.bankApp == nil)
                && other.isExpense && payment.isExpense
                && (other.currencyCode == nil || payment.currencyCode == nil || other.currencyCode == payment.currencyCode)
        }
    }

    private static func duplicateKey(_ payment: WalletPayment) -> String {
        [
            payment.isExpense ? "" : "in",
            payment.currencyCode ?? "",
            CategorySuggestionService.normalizedMerchant(payment.merchant),
            CardAccountMemory.key(forCard: payment.card) ?? ""
        ].joined(separator: "|")
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        captures = [:]
        pending = []
        matchedOccurrences = [:]
        firstCaptureAt = nil
        transferSides = []
        chargeMerges = []
        ownTransferPairs = []
        ownNames = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> Snapshot {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(captures: [:], pending: [], matchedOccurrences: [:], firstCaptureAt: nil, transferSides: [])
        }
        return decoded
    }

    private func persist() {
        let snapshot = Snapshot(
            captures: captures,
            pending: pending,
            matchedOccurrences: matchedOccurrences,
            firstCaptureAt: firstCaptureAt,
            transferSides: transferSides,
            chargeMerges: chargeMerges,
            ownTransferPairs: ownTransferPairs,
            ownNames: Array(ownNames).sorted()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
