//
//  OwnTransferMatcherTests.swift
//  TenraTests
//
//  A transfer between own accounts in two banks reaches each bank's notification as one side;
//  the matcher pairs a sending side with the receiving one (same currency, same amount or up to
//  1 % less for a fee, within 15 minutes, another card) and drops a side two days old.
//

import Testing
import Foundation
@testable import Tenra

struct OwnTransferMatcherTests {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func side(_ card: String, _ amount: Double, incoming: Bool, at offset: TimeInterval = 0, currency: String = "KZT") -> OwnTransferMatcher.Side {
        OwnTransferMatcher.Side(id: UUID().uuidString, card: card, amount: amount, currency: currency, isIncoming: incoming, date: start.addingTimeInterval(offset))
    }

    @Test("Two sides of one transfer pair up")
    func pairs() {
        let out = side("Kaspi.kz", 15_000, incoming: false)
        let into = side("Freedom •• 1234", 15_000, incoming: true, at: 40)
        let result = OwnTransferMatcher.match([out, into], now: start.addingTimeInterval(60))
        #expect(result.pairs == [.init(outgoing: out, incoming: into)])
        #expect(result.waiting.isEmpty)
    }

    @Test("A fee up to 1 % on the way still pairs; more does not")
    func fee() {
        let out = side("Kaspi.kz", 10_000, incoming: false)
        #expect(OwnTransferMatcher.match([out, side("Freedom", 9_950, incoming: true, at: 10)], now: start).pairs.count == 1)
        #expect(OwnTransferMatcher.match([out, side("Freedom", 9_800, incoming: true, at: 10)], now: start).pairs.isEmpty)
        #expect(OwnTransferMatcher.match([out, side("Freedom", 10_050, incoming: true, at: 10)], now: start).pairs.isEmpty)
    }

    @Test("Another currency, the same card or too far apart in time: no pair")
    func noPair() {
        let out = side("Kaspi.kz", 15_000, incoming: false)
        #expect(OwnTransferMatcher.match([out, side("Freedom", 15_000, incoming: true, currency: "USD")], now: start).pairs.isEmpty)
        #expect(OwnTransferMatcher.match([out, side("Kaspi.kz", 15_000, incoming: true)], now: start).pairs.isEmpty)
        #expect(OwnTransferMatcher.match([out, side("Freedom", 15_000, incoming: true, at: 16 * 60)], now: start).pairs.isEmpty)
    }

    @Test("The closest receiving side wins; a lone side waits, then ages out")
    func closestAndAge() {
        let out = side("Kaspi.kz", 5_000, incoming: false, at: 600)
        let far = side("Freedom", 5_000, incoming: true, at: 0)
        let near = side("Halyk", 5_000, incoming: true, at: 590)
        let result = OwnTransferMatcher.match([out, far, near], now: start.addingTimeInterval(700))
        #expect(result.pairs.first?.incoming == near)
        #expect(result.waiting == [far])
        #expect(OwnTransferMatcher.match([far], now: start.addingTimeInterval(49 * 3600)).waiting.isEmpty)
    }
}
