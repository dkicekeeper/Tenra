//
//  CardAccountMemoryTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CardAccountMemoryTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "card.account.\(UUID().uuidString)")!
    }

    @Test("A card is found despite case and spacing")
    func normalizedCard() {
        let memory = CardAccountMemory(defaults: makeDefaults())
        memory.remember(accountId: "a1", forCard: "Gold  Card")

        #expect(memory.accountId(forCard: " gold card ") == "a1")
        #expect(memory.accountId(forCard: "Black Card") == nil)
    }

    @Test("An empty card is never remembered")
    func emptyCard() {
        let memory = CardAccountMemory(defaults: makeDefaults())
        memory.remember(accountId: "a1", forCard: "  ")

        #expect(CardAccountMemory.key(forCard: "  ") == nil)
        #expect(memory.accountId(forCard: "") == nil)
    }

    @Test("The latest choice wins, and a forgotten card has no account")
    func latestChoiceAndForget() {
        let memory = CardAccountMemory(defaults: makeDefaults())
        memory.remember(accountId: "a1", forCard: "Gold Card")
        memory.remember(accountId: "a2", forCard: "Gold Card")
        #expect(memory.accountId(forCard: "Gold Card") == "a2")

        memory.forget(card: "gold card")
        #expect(memory.accountId(forCard: "Gold Card") == nil)
    }

    @Test("Choices survive a relaunch")
    func persistence() {
        let defaults = makeDefaults()
        CardAccountMemory(defaults: defaults).remember(accountId: "a1", forCard: "Gold Card")

        #expect(CardAccountMemory(defaults: defaults).accountId(forCard: "Gold Card") == "a1")
    }
}
