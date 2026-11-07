//
//  OwnTransferPairing.swift
//  Tenra
//
//  A transfer between two of the person's banks where neither bank says "between own
//  accounts" (that case: OwnTransferMatcher): "Перевод −100 000 ₸" in one app, "Пополнение
//  100 000 ₸" in the other. Each notification was recorded on its own, an expense and an
//  income, which counts the money twice. When the second side is recorded, the first is
//  looked up among the recorded bank notifications: the other direction, transfers or
//  top-ups (not a purchase), two different accounts, the same currency, the receiving amount
//  equal to the sent one or up to 1 % less (a fee), within 15 minutes, the closest in time.
//
//  Confident, merged without a question, when one more thing says it is the person's own:
//  the same name on both sides (money sent to oneself), a side that names the other bank
//  ("Иван П., Freedom Bank" with Freedom's app on the other side), or a name the person
//  confirmed as theirs (OwnNameMemory). Otherwise the pair is merged as a guess: To review
//  asks, and "Not a transfer" puts the expense and the income back (OwnTransferMerger).
//  Pure. docs/domains/intents.md §7.3.
//

import Foundation

nonisolated enum OwnTransferPairing {

    /// A bank notification's expense or income, as it was recorded.
    struct Side: Equatable, Sendable {
        let transactionId: String
        let payment: WalletPayment
        /// The account it was saved on.
        let accountId: String
    }

    struct Pair: Codable, Equatable, Sendable {
        let outgoingId: String
        let incomingId: String
        /// Merged without a question; otherwise a guess To review asks about.
        let isConfident: Bool
    }

    /// The pair `side` makes with one of `others` (recorded earlier, not yet paired), or nil.
    static func pair(for side: Side, among others: [Side], ownNames: Set<String>) -> Pair? {
        guard isEligible(side.payment) else { return nil }
        let candidates = others.filter { other in
            guard other.transactionId != side.transactionId,
                  isEligible(other.payment),
                  other.payment.isExpense != side.payment.isExpense,
                  other.accountId != side.accountId,
                  other.payment.currencyCode == side.payment.currencyCode,
                  abs(other.payment.date.timeIntervalSince(side.payment.date)) <= OwnTransferMatcher.window
            else { return false }
            let (outgoing, incoming) = side.payment.isExpense ? (side, other) : (other, side)
            return incoming.payment.amount <= outgoing.payment.amount + 0.005
                && incoming.payment.amount >= outgoing.payment.amount * (1 - OwnTransferMatcher.feeTolerance) - 0.005
        }
        guard let other = candidates.min(by: {
            abs($0.payment.date.timeIntervalSince(side.payment.date)) < abs($1.payment.date.timeIntervalSince(side.payment.date))
        }) else { return nil }
        let (outgoing, incoming) = side.payment.isExpense ? (side, other) : (other, side)
        return Pair(
            outgoingId: outgoing.transactionId,
            incomingId: incoming.transactionId,
            isConfident: isConfident(outgoing: outgoing.payment, incoming: incoming.payment, ownNames: ownNames)
        )
    }

    /// One more sign the money stayed with the person: the same name on both sides, a side
    /// that names the other bank, or a name they confirmed as theirs.
    static func isConfident(outgoing: WalletPayment, incoming: WalletPayment, ownNames: Set<String>) -> Bool {
        let recipient = words(outgoing.merchant)
        let sender = words(incoming.merchant)
        if !recipient.isDisjoint(with: sender) { return true }
        if !words(incoming.bankApp ?? "").isDisjoint(with: recipient) { return true }
        if !words(outgoing.bankApp ?? "").isDisjoint(with: sender) { return true }
        return [outgoing.merchant, incoming.merchant].contains { nameKey($0).map(ownNames.contains) ?? false }
    }

    /// The key a confirmed name is kept under (OwnNameMemory): the normalized counterparty.
    static func nameKey(_ counterparty: String) -> String? {
        let key = CategorySuggestionService.normalizedMerchant(counterparty)
        return key.count >= CategorySuggestionService.minimumMerchantLength ? key : nil
    }

    /// A bank notification's transfer or top-up in a known currency.
    private static func isEligible(_ payment: WalletPayment) -> Bool {
        payment.bankApp != nil && payment.isTransferLike == true && payment.currencyCode != nil
    }

    /// Words that name a bank or a person, without the ones every bank shares.
    private static func words(_ text: String) -> Set<String> {
        WalletPaymentResolver.brandWords(text).subtracting(sharedBankWords)
    }

    private static let sharedBankWords: Set<String> = [
        "bank", "банк", "банка", "банке", "банку", "superapp", "mobile", "online", "card", "карта",
        "карту", "карты", "kazakhstan", "казахстан", "qazaqstan"
    ]
}

/// Turns the pairs OwnTransferPairing found into transfers, and puts one back when the person
/// says it is not a transfer. Needs the full load: it deletes the two recorded transactions,
/// which a process launched only for an intent does not hold (it runs in the intent when the
/// app is loaded, else when the app comes to the front: MainTabView).
@MainActor
enum OwnTransferMerger {

    /// One pass at a time: the intent and the foreground both call it, and two passes over one
    /// pair would move the money twice. A pass takes the pairs queued while it runs too.
    private static var isMerging = false

    /// The waiting pairs as transfers: from the expense's account to the income's, the amounts
    /// as each bank reported them (a fee stays in the difference), on the expense's date. The
    /// expense and the income are kept in the transfer's capture for "Not a transfer". A guessed
    /// account of either side stays a guess on the transfer, so To review asks and the card's
    /// account is learned on the answer.
    static func mergePending(store: TransactionStore, captures: WalletCaptureStore = .shared) async {
        guard store.hasCompletedInitialLoad, !isMerging else { return }
        isMerging = true
        defer { isMerging = false }
        while let pair = captures.ownTransferPairs.first {
            // Taken off the queue before the first await.
            captures.removeOwnTransferPair(pair)
            await merge(pair, store: store, captures: captures)
        }
    }

    private static func merge(_ pair: OwnTransferPairing.Pair, store: TransactionStore, captures: WalletCaptureStore) async {
        guard let outgoing = store.transactionById[pair.outgoingId],
              let incoming = store.transactionById[pair.incomingId],
              outgoing.type == .expense, incoming.type == .income,
              outgoing.recurringSeriesId == nil, incoming.recurringSeriesId == nil,
              let from = outgoing.accountId, let to = incoming.accountId, from != to,
              let target = store.accounts.first(where: { $0.id == to }),
              let sent = captures.capture(forTransactionId: outgoing.id),
              let received = captures.capture(forTransactionId: incoming.id)
        else { return }
        let transfer = Transaction(
            id: "",
            date: outgoing.date,
            description: "",
            amount: outgoing.amount,
            currency: outgoing.currency,
            convertedAmount: outgoing.convertedAmount,
            type: .internalTransfer,
            category: TransactionType.transferCategoryName,
            accountId: from,
            targetAccountId: to,
            targetCurrency: incoming.convertedAmount == nil ? incoming.currency : target.currency,
            targetAmount: incoming.convertedAmount ?? incoming.amount
        )
        let saved: Transaction
        do {
            saved = try await store.add(transfer)
        } catch {
            return
        }
        // The two sides go; if either cannot, the transfer goes instead and both stay.
        var deleted: [Transaction] = []
        do {
            for side in [outgoing, incoming] {
                try await store.delete(side)
                deleted.append(side)
            }
        } catch {
            for side in deleted { _ = try? await store.add(side) }
            try? await store.delete(saved)
            return
        }

        let accountGuessed = [sent, received].contains { !$0.isReviewed && $0.guesses.contains(.account) }
        var guesses: Set<WalletCaptureStore.Guess> = pair.isConfident ? [] : [.ownTransfer]
        if accountGuessed { guesses.insert(.account) }
        captures.removeCapture(transactionId: outgoing.id)
        captures.removeCapture(transactionId: incoming.id)
        captures.insert(WalletCaptureStore.Capture(
            id: saved.id,
            payment: sent.payment,
            guesses: guesses,
            isReviewed: guesses.isEmpty,
            accountId: from,
            ownTransfer: WalletCaptureStore.OwnTransferRecord(
                incoming: received.payment,
                originals: [outgoing, incoming],
                guesses: [sent.isReviewed ? [] : sent.guesses, received.isReviewed ? [] : received.guesses]
            )
        ))
        if guesses.isEmpty {
            WalletReviewNotifier.removeDelivered(transactionId: outgoing.id)
            WalletReviewNotifier.removeDelivered(transactionId: incoming.id)
        }
    }

    /// "Not a transfer": the expense and the income come back as they were saved, with what
    /// Tenra had guessed for them, and are never paired again. They are added before the transfer
    /// goes, so a failure (a category renamed since) leaves the transfer as it was.
    static func split(transferId: String, store: TransactionStore, captures: WalletCaptureStore = .shared) async throws {
        guard let capture = captures.capture(forTransactionId: transferId),
              let record = capture.ownTransfer,
              let transfer = store.transactionById[transferId] else { return }
        var restored: [Transaction] = []
        do {
            for original in record.originals {
                restored.append(try await store.add(original))
            }
        } catch {
            for side in restored { try? await store.delete(side) }
            throw error
        }
        try await store.delete(transfer)
        captures.removeCapture(transactionId: transferId)
        let payments = [capture.payment, record.incoming]
        for (index, side) in restored.enumerated() where index < payments.count {
            let guesses = record.guesses.flatMap { index < $0.count ? $0[index] : nil } ?? []
            captures.insert(WalletCaptureStore.Capture(
                id: side.id,
                payment: payments[index],
                guesses: guesses,
                isReviewed: guesses.isEmpty,
                accountId: side.accountId,
                pairingDismissed: true
            ))
            if guesses.isEmpty {
                WalletReviewNotifier.removeDelivered(transactionId: side.id)
            }
        }
        WalletReviewNotifier.removeDelivered(transactionId: transferId)
    }
}
