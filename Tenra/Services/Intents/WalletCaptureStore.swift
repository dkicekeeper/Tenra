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

    var isExpense: Bool { isIncome != true }
}

@MainActor
@Observable
final class WalletCaptureStore {

    /// What Tenra decided on its own for a captured payment.
    enum Guess: String, Codable, Hashable {
        case category
        case account
    }

    struct Capture: Codable, Equatable, Identifiable {
        /// The saved transaction's id.
        let id: String
        let payment: WalletPayment
        var guesses: Set<Guess>
        var isReviewed: Bool

        var needsReview: Bool { !isReviewed && !guesses.isEmpty }
    }

    private struct Snapshot: Codable {
        var captures: [String: Capture]
        var pending: [WalletPayment]
        /// Subscription occurrences a payment was taken for (`[transaction id: when]`). nil in
        /// snapshots saved before it was kept.
        var matchedOccurrences: [String: Date]?
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
    /// Set by a tap on a "check a payment" notification (WalletReviewNotifier): MainTabView
    /// presents the To review list. Not persisted.
    var isReviewRequested = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = Self.load(from: defaults)
        self.captures = snapshot.captures
        self.pending = snapshot.pending
        self.matchedOccurrences = snapshot.matchedOccurrences ?? [:]
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

    func record(transactionId: String, payment: WalletPayment, guesses: Set<Guess>, now: Date = Date()) {
        guard !transactionId.isEmpty else { return }
        captures = captures.filter { now.timeIntervalSince($0.value.payment.date) <= Self.retention }
        captures[transactionId] = Capture(id: transactionId, payment: payment, guesses: guesses, isReviewed: false)
        persist()
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
        let recent = captures.values.map(\.payment) + pending
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
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> Snapshot {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(captures: [:], pending: [], matchedOccurrences: [:])
        }
        return decoded
    }

    private func persist() {
        let snapshot = Snapshot(captures: captures, pending: pending, matchedOccurrences: matchedOccurrences)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
