//
//  OnboardingCommitTests.swift
//  TenraTests
//
//  Pins TransactionStore.commitOnboarding: the first account and every starter
//  category must be in CoreData when it returns, because the first full load
//  starts right after onboarding and replaces memory with what CoreData holds.
//  The old per-item path saved only the first category (overlapping saves were
//  dropped as `savingInProgress`) and nothing at all in time for that load.
//
//  `.serialized` + `.sharedProcessState`: in-memory containers named "Tenra".
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct OnboardingCommitTests {

    private struct Fixture {
        let container: NSPersistentContainer
        let store: TransactionStore
    }

    private func makeFixture() throws -> Fixture {
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
        let store = TransactionStore(
            repository: repository,
            balanceCoordinator: BalanceCoordinator(repository: repository),
            recurringStore: RecurringStore(repository: repository)
        )
        return Fixture(container: container, store: store)
    }

    /// Fetches go to the persistent store, so the main-queue viewContext sees
    /// what the repository's background context saved.
    private func persisted<T: NSManagedObject>(_ type: T.Type, entity: String, in container: NSPersistentContainer) throws -> [T] {
        try container.viewContext.fetch(NSFetchRequest<T>(entityName: entity))
    }

    private func starterCategories() -> [CustomCategory] {
        let expenses = (1...15).map {
            CustomCategory(name: "Expense \($0)", colorHex: "#22c55e", type: .expense)
        }
        let incomes = (1...3).map {
            CustomCategory(name: "Income \($0)", colorHex: "#3b82f6", type: .income)
        }
        return expenses + incomes
    }

    @Test("The account and all categories are in CoreData when the commit returns")
    func persistsEverythingBeforeReturning() throws {
        let fixture = try makeFixture()
        let account = Account(id: "onb-account", name: "Card", currency: "KZT", balance: 0)

        try fixture.store.commitOnboarding(account: account, categories: starterCategories())

        // Read right away: no waiting for a detached save.
        let accounts = try persisted(AccountEntity.self, entity: "AccountEntity", in: fixture.container)
        let categories = try persisted(CustomCategoryEntity.self, entity: "CustomCategoryEntity", in: fixture.container)
        #expect(accounts.compactMap(\.id) == ["onb-account"])
        #expect(categories.count == 18)
        #expect(Set(categories.compactMap(\.name)).count == 18)
    }

    @Test("Memory holds the same data and import mode is left as it was")
    func memoryMatchesAndFlagRestored() throws {
        let fixture = try makeFixture()
        let account = Account(id: "onb-account", name: "Card", currency: "KZT", balance: 0)

        try fixture.store.commitOnboarding(account: account, categories: starterCategories())

        #expect(fixture.store.accounts.map(\.id) == ["onb-account"])
        #expect(fixture.store.categories.count == 18)
        #expect(!fixture.store.isImporting)
        // Order is assigned per type, in the given order.
        let expenseOrders = fixture.store.categories.filter { $0.type == .expense }.compactMap(\.order)
        #expect(expenseOrders == Array(0..<15))
    }

    @Test("A category that already exists by name and type is not added twice")
    func skipsExistingCategories() throws {
        let fixture = try makeFixture()
        try fixture.store.commitOnboarding(account: nil, categories: starterCategories())

        // Onboarding re-run: same names, new ids.
        try fixture.store.commitOnboarding(account: nil, categories: starterCategories())

        #expect(fixture.store.categories.count == 18)
        let categories = try persisted(CustomCategoryEntity.self, entity: "CustomCategoryEntity", in: fixture.container)
        #expect(categories.count == 18)
    }

    @Test("Without an account only the categories are written")
    func noAccount() throws {
        let fixture = try makeFixture()
        try fixture.store.commitOnboarding(account: nil, categories: starterCategories())

        #expect(try persisted(AccountEntity.self, entity: "AccountEntity", in: fixture.container).isEmpty)
        #expect(fixture.store.accounts.isEmpty)
    }
}
