//
//  DebtRecipientMatcherTests.swift
//  TenraTests
//
//  Pins which personal debt a receipt's recipient repays: an open "I owe" debt whose person
//  has the same first name and, when both have one, the same initial (a first name alone
//  takes only an initial after it); exactly one or none.
//

import Testing
import Foundation
@testable import Tenra

struct DebtRecipientMatcherTests {

    private func debt(_ id: String, _ person: String, _ direction: DebtDirection = .iOwe, settled: Bool = false) -> PersonalDebt {
        PersonalDebt(
            id: id, direction: direction, person: person, amount: 50_000, currency: "KZT",
            settledAt: settled ? Date() : nil
        )
    }

    private func match(_ recipient: String, _ debts: [PersonalDebt]) -> String? {
        DebtRecipientMatcher.debt(repaidTo: recipient, in: debts)?.id
    }

    @Test("A recipient with the first name and initial of a debt's person repays it")
    func matchesByNameAndInitial() {
        let debts = [debt("d1", "Иван Иванов"), debt("d2", "Асель")]
        #expect(match("Иван И.", debts) == "d1")
        #expect(match("ИВАН ИВАНОВ", debts) == "d1")
        #expect(match("Асель К.", debts) == "d2")
        #expect(match("Асель", debts) == "d2")
        #expect(match("Асель Каримова", debts) == nil)
        #expect(match("Иван П.", debts) == nil)
        #expect(match("Small", debts) == nil)
    }

    @Test("Only an open debt the person owes counts, and only when it is the only one")
    func openOwedAndUnique() {
        #expect(match("Иван И.", [debt("d1", "Иван Иванов", .owedToMe)]) == nil)
        #expect(match("Иван И.", [debt("d1", "Иван Иванов", settled: true)]) == nil)
        #expect(match("Иван", [debt("d1", "Иван Иванов"), debt("d2", "Иван Петров")]) == nil)
    }
}
