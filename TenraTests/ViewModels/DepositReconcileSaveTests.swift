//
//  DepositReconcileSaveTests.swift
//  TenraTests
//
//  The deposits pass runs at every launch for users with deposits. It saved the
//  whole accounts table once per deposit, and those saves collided with each
//  other and with a user's own account save landing at the same moment (the save
//  coordinator dropped all but the first). Recalculating interest saved twice.
//  Both now save once.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct DepositReconcileSaveTests {

    private struct Graph {
        let repo: RecordingDataRepository
        let store: TransactionStore
        let accounts: AccountsViewModel
        let deposits: DepositsViewModel
    }

    private static func dateKey(daysFromToday offset: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private static func deposit(id: String) -> Account {
        let info = DepositInfo(
            bankName: "Bank",
            initialPrincipal: 100_000,
            interestRateAnnual: 12,
            interestPostingDay: 1,
            // Calculated 40 days ago: the pass has a period to walk and moves the markers.
            lastInterestCalculationDate: dateKey(daysFromToday: -40),
            startDate: dateKey(daysFromToday: -60)
        )
        return Account(id: id, name: "Deposit \(id)", currency: "KZT", depositInfo: info,
                       initialBalance: 100_000, balance: 100_000)
    }

    /// Returns the store too: AccountsViewModel holds it weakly.
    private static func makeGraph() -> Graph {
        let repo = RecordingDataRepository()
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance,
                                     recurringStore: RecurringStore(repository: repo))
        // Memory holds every account, as after the full load.
        store.hasCompletedInitialLoad = true
        store.accounts = [
            Account(id: "card", name: "Card", currency: "KZT", initialBalance: 0, balance: 0),
            deposit(id: "d1"),
            deposit(id: "d2")
        ]
        store.rebuildAccountById()

        let accounts = AccountsViewModel(repository: repo)
        accounts.transactionStore = store
        accounts.balanceCoordinator = balance
        let deposits = DepositsViewModel(repository: repo, accountsViewModel: accounts)
        deposits.balanceCoordinator = balance
        return Graph(repo: repo, store: store, accounts: accounts, deposits: deposits)
    }

    @Test("The deposits pass saves the accounts table once, with every reconciled deposit in it")
    func reconcileAllSavesOnce() throws {
        let graph = Self.makeGraph()
        let before = graph.repo.savedAccountSnapshots.count

        var created: [Transaction] = []
        graph.deposits.reconcileAllDeposits(
            allTransactions: graph.store.transactions,
            onTransactionCreated: { created.append($0) }
        )

        let saves = Array(graph.repo.savedAccountSnapshots.dropFirst(before))
        #expect(saves.count == 1)
        let saved = try #require(saves.first)
        #expect(saved.map(\.id) == ["card", "d1", "d2"])
        for id in ["d1", "d2"] {
            let inMemory = try #require(graph.store.accountById[id]?.depositInfo)
            #expect(inMemory.lastInterestCalculationDate == Self.dateKey(daysFromToday: 0))
            #expect(saved.first { $0.id == id }?.depositInfo == inMemory)
        }
    }

    @Test("Recalculating a deposit's interest saves the accounts table once")
    func recalculateInterestSavesOnce() async throws {
        let graph = Self.makeGraph()
        let before = graph.repo.savedAccountSnapshots.count

        try await graph.deposits.recalculateInterest(for: "d1", transactionStore: graph.store)

        let saves = Array(graph.repo.savedAccountSnapshots.dropFirst(before))
        #expect(saves.count == 1)
        let saved = try #require(saves.first?.first { $0.id == "d1" })
        #expect(saved.depositInfo == graph.store.accountById["d1"]?.depositInfo)
        #expect(saved.depositInfo?.lastInterestCalculationDate == Self.dateKey(daysFromToday: 0))
    }

    @Test("A batch update with nothing changed saves nothing")
    func unchangedBatchDoesNotSave() {
        let graph = Self.makeGraph()
        let before = graph.repo.savedAccountSnapshots.count

        graph.store.updateAccounts(graph.store.accounts)

        #expect(graph.repo.savedAccountSnapshots.count == before)
    }
}
