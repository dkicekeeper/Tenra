//
//  BulkTransactionPersistenceTests.swift
//  TenraTests
//
//  The CoreData side of the bulk events: `deleteTransactions(ids:)` and
//  `updateTransactionsFields(_:)` against an in-memory store. When the store's bulk call
//  returns, CoreData holds exactly what memory holds (the save is awaited), with the same
//  fields the per-row `updateTransactionFields` writes.
//
//  `.serialized` + `.sharedProcessState`: in-memory containers named "Tenra".
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct BulkTransactionPersistenceTests {

    private struct Fixture {
        let container: NSPersistentContainer
        let store: TransactionStore
    }

    private func makeFixture() async throws -> Fixture {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }

        let repository = CoreDataRepository(stack: CoreDataStack(container: container))
        let balance = BalanceCoordinator(repository: repository)
        let store = TransactionStore(
            repository: repository,
            balanceCoordinator: balance,
            recurringStore: RecurringStore(repository: repository)
        )
        store.categories = [
            CustomCategory(name: "Food", iconSource: .sfSymbol("cart"), colorHex: "#22c55e", type: .expense),
            CustomCategory(name: "Groceries", iconSource: .sfSymbol("basket"), colorHex: "#16a34a", type: .expense)
        ]
        store.rebuildCategoryLookups()
        store.accounts = [
            Account(id: "a1", name: "Main", currency: "KZT", initialBalance: 0),
            Account(id: "a2", name: "Other", currency: "KZT", initialBalance: 0)
        ]
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)
        store.recurringStore.handleSeriesCreated(RecurringSeries(
            id: "S1", amount: 100, currency: "KZT", category: "Food", description: "Gym",
            accountId: "a1", frequency: .monthly, startDate: "2026-08-01"
        ))
        return Fixture(container: container, store: store)
    }

    private func tx(_ id: String, account: String, category: String = "", series: String? = nil) -> Transaction {
        Transaction(id: id, date: "2026-09-0\(id.last!)", description: "Magnum", amount: 100,
                    currency: "KZT", type: .expense, category: category, accountId: account,
                    recurringSeriesId: series, createdAt: 1_700_000_000)
    }

    /// Persisted rows by id. Fetches go to the store, so they see the background saves.
    private func persisted(_ container: NSPersistentContainer) throws -> [String: TransactionEntity] {
        container.viewContext.reset()
        let rows = try container.viewContext.fetch(NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity"))
        return Dictionary(rows.compactMap { entity in entity.id.map { ($0, entity) } }, uniquingKeysWith: { first, _ in first })
    }

    @Test func bulkDeleteRemovesExactlyTheRowsFromCoreData() async throws {
        let fixture = try await makeFixture()
        for row in [tx("t1", account: "a1"), tx("t2", account: "a1"), tx("t3", account: "a2"), tx("t4", account: "a1")] {
            _ = try await fixture.store.add(row)
        }
        #expect(try persisted(fixture.container).count == 4)

        await fixture.store.deleteTransactions(forAccountId: "a1")

        #expect(Set(try persisted(fixture.container).keys) == ["t3"])
        #expect(fixture.store.transactions.map(\.id) == ["t3"])
    }

    @Test func bulkUpdateWritesTheSameFieldsAsThePerRowUpdate() async throws {
        let fixture = try await makeFixture()
        for row in [tx("t1", account: "a1"), tx("t2", account: "a1"), tx("t3", account: "a2", category: "Food")] {
            _ = try await fixture.store.add(row)
        }

        let moved = await fixture.store.recategorize(ids: ["t1", "t2"], from: "", to: "Groceries")

        #expect(moved == 2)
        let rows = try persisted(fixture.container)
        #expect(rows["t1"]?.category == "Groceries")
        #expect(rows["t2"]?.category == "Groceries")
        #expect(rows["t3"]?.category == "Food")
        // Round-trips to what memory holds.
        for id in ["t1", "t2", "t3"] {
            #expect(rows[id]?.toTransaction() == fixture.store.transactionById[id])
        }
    }

    @Test func bulkUnlinkClearsTheSeriesLinkInCoreData() async throws {
        let fixture = try await makeFixture()
        for row in [tx("t1", account: "a1", category: "Food", series: "S1"),
                    tx("t2", account: "a1", category: "Food", series: "S1")] {
            _ = try await fixture.store.add(row)
        }

        let unlinked = try await fixture.store.unlinkAllTransactions(fromSeriesId: "S1")

        #expect(unlinked == 2)
        let rows = try persisted(fixture.container)
        for id in ["t1", "t2"] {
            #expect(rows[id]?.recurringSeriesId == nil)
            #expect(rows[id]?.recurringSeries == nil)
        }
    }
}
