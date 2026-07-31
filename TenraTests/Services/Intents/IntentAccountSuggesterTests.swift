//
//  IntentAccountSuggesterTests.swift
//  TenraTests
//
//  `.serialized` for the same reason as SpendingQueryServiceTests: parallel
//  in-memory containers sharing a name can share backing stores.
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized)
struct IntentAccountSuggesterTests {

    // MARK: - Fixtures

    private func makeContext() throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }
        return container.viewContext
    }

    private func account(_ id: String) -> Account {
        Account(id: id, name: id, currency: "KZT", balance: 100_000)
    }

    private func seed(
        in context: NSManagedObjectContext,
        category: String,
        accountId: String,
        dateKey: String
    ) throws {
        let entity = TransactionEntity(context: context)
        entity.id = UUID().uuidString
        entity.date = DateFormatters.dateFormatter.date(from: dateKey)
        entity.amount = 1000
        entity.currency = "KZT"
        entity.type = TransactionType.expense.rawValue
        entity.category = category
        entity.accountId = accountId
        try context.save()
    }

    // MARK: - Tests

    @Test("With no history for the category, nothing is suggested")
    func noHistoryYieldsNil() throws {
        let context = try makeContext()
        let suggestion = IntentAccountSuggester.suggestedAccountId(
            forCategory: "Еда вне дома",
            accounts: [account("a1"), account("a2")],
            amount: 3000,
            context: context
        )
        #expect(suggestion == nil)
    }

    @Test("An empty category name is never looked up")
    func emptyCategoryYieldsNil() throws {
        let context = try makeContext()
        try seed(in: context, category: "", accountId: "a2", dateKey: "2026-07-30")
        let suggestion = IntentAccountSuggester.suggestedAccountId(
            forCategory: "",
            accounts: [account("a1"), account("a2")],
            amount: nil,
            context: context
        )
        #expect(suggestion == nil)
    }

    @Test("The account actually used for that category is suggested")
    func suggestsAccountUsedForCategory() throws {
        let context = try makeContext()
        // a2 is the only account ever used for this category, and it is not the
        // first in the accounts array, so a naive "first eligible" would miss it.
        for day in ["2026-07-20", "2026-07-25", "2026-07-30"] {
            try seed(in: context, category: "Еда вне дома", accountId: "a2", dateKey: day)
        }

        let suggestion = IntentAccountSuggester.suggestedAccountId(
            forCategory: "Еда вне дома",
            accounts: [account("a1"), account("a2")],
            amount: 3000,
            context: context
        )
        #expect(suggestion == "a2")
    }

    @Test("History for a different category does not leak into the suggestion")
    func otherCategoryHistoryIsIgnored() throws {
        let context = try makeContext()
        try seed(in: context, category: "Транспорт", accountId: "a2", dateKey: "2026-07-30")

        let suggestion = IntentAccountSuggester.suggestedAccountId(
            forCategory: "Еда вне дома",
            accounts: [account("a1"), account("a2")],
            amount: nil,
            context: context
        )
        #expect(suggestion == nil)
    }
}
