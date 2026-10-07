//
//  BalancePersistOrderTests.swift
//  TenraTests
//
//  Every balance change used to start its own detached save of the full value, so a
//  burst could finish out of order and leave an older balance in CoreData; the next
//  launch shows the persisted balance. Writes now go through one serial queue that
//  keeps the newest value per account, so the last write is always the newest.
//
//  The repository delays early writes longer than later ones: concurrent writers
//  would finish in reverse order, a serial writer cannot.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct BalancePersistOrderTests {

    private func makeCoordinator() async -> (BalanceCoordinator, RecordingDataRepository, Account, Account) {
        let repo = RecordingDataRepository()
        // Write #0 takes 60 ms, #1 50 ms, ... later writes finish at once.
        repo.balanceWriteDelay = { index in .milliseconds(max(0, 60 - index * 10)) }
        let coordinator = BalanceCoordinator(repository: repo)
        let card = Account(id: "card", name: "Card", currency: "KZT", initialBalance: 0, balance: 0)
        let cash = Account(id: "cash", name: "Cash", currency: "KZT", initialBalance: 0, balance: 0)
        await coordinator.registerAccounts([card, cash])
        return (coordinator, repo, card, cash)
    }

    private static func today() -> String {
        DateFormatters.dateFormatter.string(from: Date())
    }

    @Test("A burst of balance changes persists the newest balance last")
    func burstPersistsNewestLast() async {
        let (coordinator, repo, card, _) = await makeCoordinator()

        for step in 1...30 {
            await coordinator.updateForAccount(card, newBalance: Double(step))
        }
        await coordinator.waitForPersistedBalances()

        let written = repo.balanceWrites.compactMap { $0["card"] }
        #expect(written.last == 30)
        // Batches are written in the order the values were computed.
        #expect(written == written.sorted())
        // Values queued behind a running write collapse into one write.
        #expect(written.count < 30)
    }

    @Test("Incremental changes and a recalculation of several accounts all land at their newest value")
    func incrementalAndRecalcInterleave() async {
        let (coordinator, repo, card, cash) = await makeCoordinator()
        let day = Self.today()

        for index in 0..<10 {
            let expense = Transaction(
                id: "e\(index)", date: day, description: "", amount: 10, currency: "KZT",
                type: .expense, category: "", accountId: index.isMultiple(of: 2) ? "card" : "cash"
            )
            await coordinator.updateForTransaction(expense, operation: .add(expense))
        }
        await coordinator.recalculateAll(accounts: [card, cash], transactions: [])
        await coordinator.updateForAccount(cash, newBalance: 7)
        await coordinator.waitForPersistedBalances()

        var lastWritten: [String: Double] = [:]
        for batch in repo.balanceWrites {
            lastWritten.merge(batch) { _, newer in newer }
        }
        #expect(lastWritten["card"] == coordinator.balances["card"])
        #expect(lastWritten["cash"] == 7)
        #expect(coordinator.balances["cash"] == 7)
    }
}
