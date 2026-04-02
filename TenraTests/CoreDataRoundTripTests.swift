//
//  CoreDataRoundTripTests.swift
//  AIFinanceManagerTests
//
//  TEST-04: CoreData round-trip integration test
//  Verifies that TransactionEntity saved to an in-memory NSPersistentContainer
//  survives the save-reload cycle with all fields intact.
//
//  Created 2026-03-02
//

import Testing
import CoreData
import Foundation
@testable import AIFinanceManager

// MARK: - Suite

/// Run serially to prevent NSInMemoryStoreType cross-test contamination.
/// Swift Testing runs tests in parallel by default; parallel in-memory containers
/// with the same name can share backing stores, causing flaky count assertions.
@Suite("CoreData Round-Trip Tests", .serialized)
struct CoreDataRoundTripTests {

    // MARK: - Helpers

    /// Creates an isolated in-memory NSPersistentContainer.
    /// Uses the same NSManagedObjectModel as production (loaded from app bundle).
    /// Each call gets a fresh, independent store.
    private func makeInMemoryContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "AIFinanceManager")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        // Use a unique URL to guarantee store isolation between parallel test runs.
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let error = loadError { throw error }
        return container
    }

    /// Factory that builds a Transaction with sensible defaults, allowing per-test overrides.
    private func makeTransaction(
        id: String = UUID().uuidString,
        date: String = "2026-01-15",
        description: String = "Groceries",
        amount: Double = 150.50,
        currency: String = "KZT",
        type: TransactionType = .expense,
        category: String = "Food",
        subcategory: String? = nil,
        accountId: String? = "acc-1",
        accountName: String? = "Wallet",
        convertedAmount: Double? = nil,
        createdAt: TimeInterval = 1_700_000_000
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: type,
            category: category,
            subcategory: subcategory,
            accountId: accountId,
            accountName: accountName,
            createdAt: createdAt
        )
    }

    // MARK: - Test A: Full round-trip scalar fields

    @Test("Test A: Full round-trip scalar fields")
    func testFullRoundTripScalarFields() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext
        let transaction = makeTransaction()

        // 1. Create entity and save (triggers willSave → dateSectionKey auto-set)
        context.performAndWait {
            _ = TransactionEntity.from(transaction, context: context)
            try? context.save()
        }

        // 2. Evict from identity map so fetch re-reads from store
        context.performAndWait {
            context.reset()
        }

        // 3. Reload by id predicate
        var roundTripped: Transaction?
        var fetchError: Error?
        context.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", transaction.id)
            do {
                let results = try context.fetch(request)
                roundTripped = results.first?.toTransaction()
            } catch {
                fetchError = error
            }
        }

        if let fetchError { throw fetchError }
        let result = try #require(roundTripped)
        #expect(result.id == transaction.id)
        #expect(result.date == "2026-01-15")
        #expect(result.amount == 150.50)
        #expect(result.currency == "KZT")
        #expect(result.type == .expense)
        #expect(result.category == "Food")
        #expect(result.accountId == "acc-1")
        #expect(result.accountName == "Wallet")
        #expect(result.description == "Groceries")
        // createdAt stored as Date and restored as TimeInterval — compare with tolerance
        #expect(abs(result.createdAt - transaction.createdAt) < 1.0)
    }

    // MARK: - Test B: dateSectionKey auto-populated by willSave()

    @Test("Test B: dateSectionKey auto-populated by willSave()")
    func testDateSectionKeyAutoPopulated() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext
        let transaction = makeTransaction(date: "2026-01-15")

        context.performAndWait {
            _ = TransactionEntity.from(transaction, context: context)
            try? context.save()
            context.reset()
        }

        var sectionKey: String?
        var fetchError: Error?
        context.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", transaction.id)
            do {
                let results = try context.fetch(request)
                sectionKey = results.first?.dateSectionKey
            } catch {
                fetchError = error
            }
        }

        if let fetchError { throw fetchError }
        // dateSectionKey must equal the transaction's date string
        #expect(sectionKey == "2026-01-15")
    }

    // MARK: - Test C: nil optional fields preserved

    @Test("Test C: nil optional fields preserved")
    func testNilOptionalFieldsPreserved() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext
        let transaction = makeTransaction(
            subcategory: nil,
            accountId: nil,
            convertedAmount: nil
        )

        context.performAndWait {
            _ = TransactionEntity.from(transaction, context: context)
            try? context.save()
            context.reset()
        }

        var roundTripped: Transaction?
        var fetchError: Error?
        context.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", transaction.id)
            do {
                let results = try context.fetch(request)
                roundTripped = results.first?.toTransaction()
            } catch {
                fetchError = error
            }
        }

        if let fetchError { throw fetchError }
        let result = try #require(roundTripped)
        #expect(result.subcategory == nil)
        #expect(result.targetAccountId == nil)
        #expect(result.convertedAmount == nil)
    }

    // MARK: - Test D: multiple transactions in store

    @Test("Test D: multiple transactions maintain correct count and unique IDs")
    func testMultipleTransactionsInStore() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext
        let t1 = makeTransaction(id: UUID().uuidString, description: "Tx1")
        let t2 = makeTransaction(id: UUID().uuidString, description: "Tx2")
        let t3 = makeTransaction(id: UUID().uuidString, description: "Tx3")

        context.performAndWait {
            _ = TransactionEntity.from(t1, context: context)
            _ = TransactionEntity.from(t2, context: context)
            _ = TransactionEntity.from(t3, context: context)
            try? context.save()
            context.reset()
        }

        var fetchedIds: Set<String> = []
        var count = 0
        var fetchError: Error?
        context.performAndWait {
            do {
                let all = try context.fetch(TransactionEntity.fetchRequest())
                count = all.count
                fetchedIds = Set(all.compactMap(\.id))
            } catch {
                fetchError = error
            }
        }

        if let fetchError { throw fetchError }
        #expect(count == 3)
        #expect(fetchedIds.count == 3)
        #expect(fetchedIds.contains(t1.id))
        #expect(fetchedIds.contains(t2.id))
        #expect(fetchedIds.contains(t3.id))
    }

    // MARK: - Test E: convertedAmount = nil round-trips as nil (stored as 0.0)

    @Test("Test E: convertedAmount nil stored as 0.0, returned as nil by toTransaction()")
    func testConvertedAmountNilRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext
        let transaction = makeTransaction(convertedAmount: nil)

        var entityStoredValue: Double = -1
        context.performAndWait {
            let entity = TransactionEntity.from(transaction, context: context)
            // Verify the entity stores 0.0 before save
            entityStoredValue = entity.convertedAmount
            try? context.save()
            context.reset()
        }
        #expect(entityStoredValue == 0.0)

        var roundTripped: Transaction?
        var fetchError: Error?
        context.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", transaction.id)
            do {
                let results = try context.fetch(request)
                roundTripped = results.first?.toTransaction()
            } catch {
                fetchError = error
            }
        }

        if let fetchError { throw fetchError }
        let result = try #require(roundTripped)
        // toTransaction() treats 0.0 as nil
        #expect(result.convertedAmount == nil)
    }

    // MARK: - Test F: transaction type round-trip (.income)

    @Test("Test F: transaction type .income survives round-trip")
    func testTransactionTypeIncomeRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext
        let transaction = makeTransaction(type: .income, category: "Salary")

        context.performAndWait {
            _ = TransactionEntity.from(transaction, context: context)
            try? context.save()
            context.reset()
        }

        var roundTripped: Transaction?
        var rawType: String?
        var fetchError: Error?
        context.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", transaction.id)
            do {
                let results = try context.fetch(request)
                roundTripped = results.first?.toTransaction()
                rawType = results.first?.type
            } catch {
                fetchError = error
            }
        }

        if let fetchError { throw fetchError }
        let result = try #require(roundTripped)
        #expect(result.type == .income)
        #expect(result.category == "Salary")
        // The entity stores the rawValue string "income"
        #expect(rawType == "income")
    }
}
