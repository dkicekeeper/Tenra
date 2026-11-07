//
//  OwnTransferPairingTests.swift
//  TenraTests
//
//  A transfer between two banks the person holds, where neither bank says "between own
//  accounts": "Перевод −100 000" in one app, "Пополнение 100 000" in the other. Both were
//  recorded (an expense and an income); the pair becomes one transfer. Invented values.
//  docs/domains/intents.md §7.3.
//

import Testing
import Foundation
@testable import Tenra

@Suite("OwnTransferPairing")
struct OwnTransferPairingTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func side(
        _ id: String,
        _ amount: Double,
        incoming: Bool,
        app: String? = "Freedom",
        party: String = "",
        account: String,
        after seconds: TimeInterval = 0,
        currency: String? = "KZT",
        isTransfer: Bool? = true
    ) -> OwnTransferPairing.Side {
        OwnTransferPairing.Side(
            transactionId: id,
            payment: WalletPayment(
                id: "p-\(id)",
                amount: amount,
                currencyCode: currency,
                merchant: party,
                card: "\(app ?? "Wallet") •• 0000",
                accountId: nil,
                date: t0.addingTimeInterval(seconds),
                bankApp: app,
                isIncome: incoming,
                isTransferLike: isTransfer
            ),
            accountId: account
        )
    }

    private func pair(_ new: OwnTransferPairing.Side, _ others: [OwnTransferPairing.Side], own: Set<String> = []) -> OwnTransferPairing.Pair? {
        OwnTransferPairing.pair(for: new, among: others, ownNames: own)
    }

    @Test("The same person on both sides is the person's own transfer")
    func samePersonIsConfident() {
        let out = side("out", 100_000, incoming: false, app: "Freedom", party: "Daulet K.", account: "freedom")
        let inc = side("in", 100_000, incoming: true, app: "Kaspi.kz", party: "Daulet K.", account: "kaspi", after: 40)
        #expect(pair(inc, [out]) == OwnTransferPairing.Pair(outgoingId: "out", incomingId: "in", isConfident: true))
        // Whichever side arrives second finds the first.
        #expect(pair(out, [inc]) == OwnTransferPairing.Pair(outgoingId: "out", incomingId: "in", isConfident: true))
    }

    @Test("A side that names the other bank is confident")
    func otherBankNamed() {
        let out = side("out", 50_000, incoming: false, app: "Kaspi.kz", party: "Иван П.", account: "kaspi")
        let inc = side("in", 50_000, incoming: true, app: "Freedom", party: "Kaspi Bank", account: "freedom", after: 60)
        #expect(pair(inc, [out])?.isConfident == true)
    }

    @Test("Only the amount and the time: a pair, but a guess")
    func amountAndTimeOnly() {
        let out = side("out", 5_000, incoming: false, app: "Freedom", party: "Иван П.", account: "freedom")
        let inc = side("in", 5_000, incoming: true, app: "Kaspi.kz", party: "Мария С.", account: "kaspi", after: 300)
        #expect(pair(inc, [out]) == OwnTransferPairing.Pair(outgoingId: "out", incomingId: "in", isConfident: false))
    }

    @Test("A name the person confirmed as theirs is confident")
    func rememberedOwnName() {
        let out = side("out", 5_000, incoming: false, app: "Freedom", party: "Алия Н.", account: "freedom")
        let inc = side("in", 5_000, incoming: true, app: "Kaspi.kz", party: "", account: "kaspi", after: 30)
        #expect(pair(inc, [out])?.isConfident == false)
        #expect(pair(inc, [out], own: [OwnTransferPairing.nameKey("Алия Н.") ?? ""])?.isConfident == true)
    }

    @Test("The receiving side may be up to one percent less: the sending bank's fee")
    func feeTolerance() {
        let out = side("out", 100_100, incoming: false, account: "freedom")
        #expect(pair(side("in", 100_000, incoming: true, app: "Kaspi.kz", account: "kaspi", after: 20), [out]) != nil)
        #expect(pair(side("in", 98_000, incoming: true, app: "Kaspi.kz", account: "kaspi", after: 20), [out]) == nil)
        #expect(pair(side("in", 100_200, incoming: true, app: "Kaspi.kz", account: "kaspi", after: 20), [out]) == nil)
    }

    @Test("No pair: a purchase, the same account, over fifteen minutes, another currency, Apple Pay")
    func noPair() {
        let inc = side("in", 5_000, incoming: true, app: "Kaspi.kz", account: "kaspi")
        #expect(pair(inc, [side("buy", 5_000, incoming: false, account: "freedom", isTransfer: false)]) == nil)
        #expect(pair(inc, [side("same", 5_000, incoming: false, account: "kaspi")]) == nil)
        #expect(pair(inc, [side("late", 5_000, incoming: false, account: "freedom", after: 16 * 60)]) == nil)
        #expect(pair(inc, [side("usd", 5_000, incoming: false, account: "freedom", currency: "USD")]) == nil)
        #expect(pair(inc, [side("pay", 5_000, incoming: false, app: nil, account: "freedom")]) == nil)
        #expect(pair(inc, [side("both-in", 5_000, incoming: true, account: "freedom")]) == nil)
    }

    @Test("The closest side in time wins")
    func closestWins() {
        let inc = side("in", 5_000, incoming: true, app: "Kaspi.kz", account: "kaspi", after: 600)
        let early = side("early", 5_000, incoming: false, account: "freedom")
        let close = side("close", 5_000, incoming: false, account: "halyk", after: 590)
        #expect(pair(inc, [early, close])?.outgoingId == "close")
    }
}
