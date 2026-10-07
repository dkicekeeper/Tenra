//
//  LoadWindowMergeTests.swift
//  TenraTests
//
//  The full load (`TransactionStore.loadData`) used to replace memory with rows it
//  fetched before the user's change: an account or category created right after
//  launch vanished, and the next save of that table deleted it from CoreData.
//  Before the load the subcategory and link tables are empty in memory, and saving
//  one of them (each save replaces the whole table) wiped it: creating a subcategory
//  in the first seconds deleted every other one.
//
//  Now changes made while a load is in flight (or before the first one) are folded
//  into what it fetched, and whole-table saves wait until memory holds the table.
//
//  The repository holds `loadTransactions` on a gate, so the test acts while the
//  load is in flight. `.serialized` + `.sharedProcessState`: loadData reconciles the
//  process-wide account and category order managers (UserDefaults.standard).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct LoadWindowMergeTests {

    private struct Graph {
        let repo: RecordingDataRepository
        let balance: BalanceCoordinator
        let store: TransactionStore
    }

    private static func day(_ offset: Int) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private static var card: Account {
        Account(id: "a", name: "Card", currency: "KZT", initialBalance: 0, balance: 0)
    }
    private static var food: CustomCategory {
        CustomCategory(id: "food", name: "Food", colorHex: "#22c55e", type: .expense)
    }
    private static var foodLink: CategorySubcategoryLink {
        CategorySubcategoryLink(id: "food-s1", categoryId: "food", subcategoryId: "s1")
    }
    private static var txLink: TransactionSubcategoryLink {
        TransactionSubcategoryLink(id: "t1-s1", transactionId: "t1", subcategoryId: "s1")
    }

    private static func expense(_ id: String, _ amount: Double, category: String, account: String, on offset: Int) -> Transaction {
        Transaction(id: id, date: day(offset), description: id, amount: amount, currency: "KZT",
                    type: .expense, category: category, accountId: account)
    }

    /// CoreData as it was before launch, and a store that has run the fast path only.
    private static func makeGraph() -> Graph {
        let repo = RecordingDataRepository()
        repo.saveAccounts([card])
        repo.saveCategories([food])
        repo.saveSubcategories([Subcategory(id: "s1", name: "Coffee"), Subcategory(id: "s2", name: "Lunch")])
        repo.saveCategorySubcategoryLinks([foodLink])
        repo.saveTransactionSubcategoryLinks([txLink])
        repo.saveTransactions([expense("t1", 10, category: "Food", account: "a", on: -1)])
        // A warm aggregate table, written before launch.
        repo.persistedCategoryAggregates = [
            CategoryAggregate(categoryName: "Food", year: 0, month: 0, totalAmount: 10, transactionCount: 1, currency: "KZT")
        ]

        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance,
                                     recurringStore: RecurringStore(repository: repo))
        // What `loadAccountsOnly` does at launch (it reads CoreDataStack.shared, so a test
        // can't call it): every account and category in memory, nothing else.
        store.accounts = [card]
        store.rebuildAccountById()
        store.categories = [food]
        store.rebuildCategoryLookups()
        store.hasLoadedAccountsAndCategories = true
        return Graph(repo: repo, balance: balance, store: store)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func allTimeTotal(_ store: TransactionStore, _ category: String) -> Double? {
        store.categoryAggregatesByKey[CategoryAggregate.makeId(category: category, year: 0, month: 0)]?.totalAmount
    }

    // MARK: - First load

    @Test("Changes made while the first load runs are merged into it, and saved once it lands")
    func changesDuringFirstLoadAreKept() async throws {
        let graph = Self.makeGraph()
        let store = graph.store
        let gate = LoadGate()
        graph.repo.loadTransactionsGate = gate

        let load = Task { try await store.loadData() }
        #expect(await waitUntil { gate.isWaiting })

        // The user acts before the load lands.
        let travel = CustomCategory(id: "travel", name: "Travel", colorHex: "#3b82f6", type: .expense)
        let travelLink = CategorySubcategoryLink(id: "travel-s3", categoryId: "travel", subcategoryId: "s3")
        store.addAccount(Account(id: "b", name: "Cash", currency: "KZT", initialBalance: 0, balance: 0))
        store.addCategory(travel)
        store.addSubcategory(Subcategory(id: "s3", name: "Taxi"))
        store.updateCategorySubcategoryLinks(store.categorySubcategoryLinks + [travelLink])
        let taxi = try await store.add(Self.expense("t2", 25, category: "Travel", account: "b", on: 0))

        // Nothing was written from partial memory: no table lost a row.
        #expect(graph.repo.loadAccounts().map(\.id) == ["a"])
        #expect(graph.repo.loadCategories().map(\.id) == ["food"])
        #expect(Set(graph.repo.loadSubcategories().map(\.id)) == ["s1", "s2"])
        #expect(graph.repo.loadCategorySubcategoryLinks().map(\.id) == ["food-s1"])

        gate.open()
        try await load.value

        // Memory holds what was fetched plus what changed meanwhile.
        #expect(Set(store.accounts.map(\.id)) == ["a", "b"])
        #expect(Set(store.categories.map(\.id)) == ["food", "travel"])
        #expect(Set(store.subcategories.map(\.id)) == ["s1", "s2", "s3"])
        #expect(Set(store.categorySubcategoryLinks.map(\.id)) == ["food-s1", "travel-s3"])
        #expect(store.transactionSubcategoryLinks.map(\.id) == ["t1-s1"])
        #expect(Set(store.transactions.map(\.id)) == ["t1", taxi.id])
        #expect(store.transactionsByAccount["b"]?.map(\.id) == [taxi.id])
        #expect(store.subcategoryIdsByCategoryId["travel"] == ["s3"])
        // The warm aggregate table predates the new expense: rebuilt from the transactions.
        #expect(allTimeTotal(store, "Food") == 10)
        #expect(allTimeTotal(store, "Travel") == 25)

        // The held saves ran with the merged tables.
        #expect(Set(graph.repo.loadAccounts().map(\.id)) == ["a", "b"])
        #expect(Set(graph.repo.loadCategories().map(\.id)) == ["food", "travel"])
        #expect(Set(graph.repo.loadSubcategories().map(\.id)) == ["s1", "s2", "s3"])
        #expect(await waitUntil {
            Set(graph.repo.loadCategorySubcategoryLinks().map(\.id)) == ["food-s1", "travel-s3"]
        })
        #expect(graph.repo.loadTransactionSubcategoryLinks().map(\.id) == ["t1-s1"])
    }

    @Test("A subcategory created before the first load does not wipe the table")
    func subcategoryBeforeLoadWaitsForIt() async throws {
        let graph = Self.makeGraph()

        graph.store.addSubcategory(Subcategory(id: "s3", name: "Taxi"))
        #expect(Set(graph.repo.loadSubcategories().map(\.id)) == ["s1", "s2"])

        try await graph.store.loadData()

        #expect(Set(graph.store.subcategories.map(\.id)) == ["s1", "s2", "s3"])
        #expect(Set(graph.repo.loadSubcategories().map(\.id)) == ["s1", "s2", "s3"])
    }

    @Test("Before the full load, account saves run once the fast path loaded every account")
    func accountSavesAfterFastPathAreNotHeld() {
        let graph = Self.makeGraph()

        graph.store.addAccount(Account(id: "b", name: "Cash", currency: "KZT", initialBalance: 0, balance: 0))

        #expect(Set(graph.repo.loadAccounts().map(\.id)) == ["a", "b"])
        // Tables only the full load fills stay held.
        #expect(!graph.store.holdsCompleteTable(.subcategories))
    }

    // MARK: - Reload (restore, reset)

    @Test("Edits made while a reload runs survive it")
    func changesDuringReloadAreKept() async throws {
        let graph = Self.makeGraph()
        let store = graph.store
        try await store.loadData()
        #expect(store.hasCompletedInitialLoad)

        let gate = LoadGate()
        graph.repo.loadTransactionsGate = gate
        let reload = Task { try await store.loadData() }
        #expect(await waitUntil { gate.isWaiting })

        var renamed = Self.food
        renamed.name = "Groceries"
        store.updateCategory(renamed)
        store.updateSubcategories(store.subcategories.filter { $0.id != "s2" })
        let lunch = try await store.add(Self.expense("t3", 7, category: "Groceries", account: "a", on: 0))

        gate.open()
        try await reload.value

        #expect(store.categories.map(\.name) == ["Groceries"])
        // The rename reached the loaded transaction too.
        #expect(store.transactionById["t1"]?.category == "Groceries")
        #expect(Set(store.subcategories.map(\.id)) == ["s1"])
        #expect(Set(store.transactions.map(\.id)) == ["t1", lunch.id])
        #expect(allTimeTotal(store, "Groceries") == 17)
        #expect(graph.repo.loadCategories().map(\.name) == ["Groceries"])
        #expect(graph.repo.loadSubcategories().map(\.id) == ["s1"])
    }

    @Test("A second load waits for the one in flight")
    func loadsDoNotOverlap() async throws {
        let graph = Self.makeGraph()
        let gate = LoadGate()
        graph.repo.loadTransactionsGate = gate

        let first = Task { try await graph.store.loadData() }
        #expect(await waitUntil { gate.isWaiting })
        let second = Task { try await graph.store.loadData() }
        // The second load has not started fetching: it is waiting for the first.
        #expect(await waitUntil { graph.store.loadWaiters.count == 1 })
        #expect(graph.store.isLoadInFlight)

        gate.open()
        try await first.value
        try await second.value

        #expect(!graph.store.isLoadInFlight)
        #expect(graph.store.hasCompletedInitialLoad)
    }

    // MARK: - App Intents

    @Test("An intent linking subcategories while the app's load runs waits for it and links through memory")
    func intentLinkWaitsForLoadInFlight() async throws {
        let graph = Self.makeGraph()
        let store = graph.store
        let categories = CategoriesViewModel(repository: graph.repo)
        categories.transactionStore = store
        categories.setupTransactionStoreObserver()
        var directLinks = 0
        let hooks = CommitHooks(
            recordLearning: { _, _ in },
            recordRating: {},
            linkSubcategoriesBeforeFullLoad: { _, _ in directLinks += 1 }
        )
        let draft = TransactionDraft(
            type: .expense, amount: 3000, currency: "KZT", convertedAmount: nil,
            categoryName: "Food", subcategoryIds: ["s2"], accountId: "a",
            date: Date(), note: "Coffee House", warnings: []
        )

        let gate = LoadGate()
        graph.repo.loadTransactionsGate = gate
        let load = Task { try await store.loadData() }
        #expect(await waitUntil { gate.isWaiting })

        let commit = Task {
            try await TransactionDraftService.commit(draft, store: store, categoriesViewModel: categories, hooks: hooks)
        }
        // The commit saved its transaction and now waits for the load before linking.
        #expect(await waitUntil { store.loadWaiters.count == 1 })
        gate.open()
        try await load.value
        let saved = try await commit.value

        #expect(directLinks == 0)
        #expect(store.subcategoryIdsByTransactionId[saved.id] == ["s2"])
        // The other transaction's link survived the whole-table save.
        #expect(await waitUntil {
            let links = graph.repo.loadTransactionSubcategoryLinks()
            return links.contains { $0.transactionId == saved.id && $0.subcategoryId == "s2" }
                && links.contains { $0.id == "t1-s1" }
        })
    }
}
