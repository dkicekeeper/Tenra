//
//  OwnTransferMatcher.swift
//  Tenra
//
//  A transfer between the user's own accounts in two banks reaches each bank's notification as
//  one side: "−15 000" in one app, "+15 000 between own accounts" in the other. Recorded alone,
//  either side would count the money twice (an expense here, an income there), so
//  LogBankNotificationIntent queues the sides (WalletCaptureStore.transferSides) and the app pairs
//  them when it comes to the front (the background intent has no history to edit): same currency,
//  the receiving amount equal to the sent one or up to 1 % less (a fee), within 15 minutes, two
//  different cards. A pair whose cards both have an account (CardAccountMemory) becomes one
//  internal transfer; a side left alone for two days is dropped, as before pairing existed.
//  docs/domains/intents.md §7.3, docs/plan-notification-capture.md §7.
//

import Foundation

nonisolated enum OwnTransferMatcher {
    /// One side of a transfer between own accounts, as a bank's notification reported it.
    nonisolated struct Side: Codable, Equatable, Identifiable, Sendable {
        let id: String
        /// The card key (BankNotificationParser.cardName): the bank's app and the card's digits.
        let card: String
        let amount: Double
        /// ISO 4217.
        let currency: String
        let isIncoming: Bool
        let date: Date
    }

    nonisolated struct Pair: Equatable, Sendable {
        let outgoing: Side
        let incoming: Side
    }

    /// The two notifications of one transfer arrive this close together.
    static let window: TimeInterval = 15 * 60
    /// The receiving side may be this much smaller than the sent one: a fee.
    static let feeTolerance = 0.01
    /// A side nobody paired after this long stays unrecorded.
    static let maxAge: TimeInterval = 48 * 60 * 60

    /// Pairs each sending side with the closest receiving side in time that fits; what is
    /// neither paired nor too old is left for later.
    static func match(_ sides: [Side], now: Date) -> (pairs: [Pair], waiting: [Side]) {
        let fresh = sides.filter { now.timeIntervalSince($0.date) <= maxAge }
        var incoming = fresh.filter(\.isIncoming)
        var pairs: [Pair] = []
        var paired = Set<String>()
        for outgoing in fresh.filter({ !$0.isIncoming }).sorted(by: { $0.date < $1.date }) {
            let candidates = incoming.enumerated().filter { _, side in
                side.currency == outgoing.currency
                    && side.card != outgoing.card
                    && abs(side.date.timeIntervalSince(outgoing.date)) <= window
                    && side.amount <= outgoing.amount + 0.005
                    && side.amount >= outgoing.amount * (1 - feeTolerance) - 0.005
            }
            guard let best = candidates.min(by: {
                abs($0.element.date.timeIntervalSince(outgoing.date)) < abs($1.element.date.timeIntervalSince(outgoing.date))
            }) else { continue }
            pairs.append(Pair(outgoing: outgoing, incoming: best.element))
            paired.formUnion([outgoing.id, best.element.id])
            incoming.remove(at: best.offset)
        }
        return (pairs, fresh.filter { !paired.contains($0.id) })
    }
}

/// Records the paired sides as transfers, in the app's process.
enum OwnTransferRecorder {
    /// Runs when the app comes to the front (MainTabView) and after a bank notification queued a
    /// side while the app was running.
    static func recordPairs(
        services: IntentServices,
        captures: WalletCaptureStore = .shared,
        cards: CardAccountMemory = .shared,
        now: Date = Date()
    ) async {
        guard !captures.transferSides.isEmpty else { return }
        let (pairs, waiting) = OwnTransferMatcher.match(captures.transferSides, now: now)
        var keep = waiting
        for pair in pairs {
            guard let from = cards.accountId(forCard: pair.outgoing.card),
                  let to = cards.accountId(forCard: pair.incoming.card),
                  from != to,
                  let source = services.store.accounts.first(where: { $0.id == from }),
                  let target = services.store.accounts.first(where: { $0.id == to }),
                  source.currency == pair.outgoing.currency,
                  target.currency == pair.incoming.currency else {
                // Not both accounts known yet: wait, the person may set the card's account.
                keep += [pair.outgoing, pair.incoming]
                continue
            }
            do {
                try await services.store.transfer(
                    from: from,
                    to: to,
                    amount: pair.outgoing.amount,
                    currency: pair.outgoing.currency,
                    targetAmount: pair.incoming.amount,
                    targetCurrency: pair.incoming.currency,
                    date: FastDateParser.string(from: pair.outgoing.date),
                    description: ""
                )
            } catch {
                keep += [pair.outgoing, pair.incoming]
            }
        }
        captures.setTransferSides(keep)
    }
}
