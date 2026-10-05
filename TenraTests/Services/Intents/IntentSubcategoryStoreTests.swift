//
//  IntentSubcategoryStoreTests.swift
//  TenraTests
//
//  `.serialized` + `.sharedProcessState` for the same reason as
//  IntentAccountSuggesterTests: in-memory containers named "Tenra" built by
//  parallel suites can share backing stores.
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct IntentSubcategoryStoreTests {

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

    private func seedSubcategory(_ id: String, name: String, in context: NSManagedObjectContext) {
        let entity = SubcategoryEntity(context: context)
        entity.id = id
        entity.name = name
    }

    private func seedCategoryLink(category: String, subcategory: String, order: Int64, in context: NSManagedObjectContext) {
        let entity = CategorySubcategoryLinkEntity(context: context)
        entity.id = UUID().uuidString
        entity.categoryId = category
        entity.subcategoryId = subcategory
        entity.sortOrder = order
    }

    private func seedTransactionLink(transaction: String, subcategory: String, in context: NSManagedObjectContext) {
        let entity = TransactionSubcategoryLinkEntity(context: context)
        entity.id = UUID().uuidString
        entity.transactionId = transaction
        entity.subcategoryId = subcategory
    }

    private func transactionLinks(in context: NSManagedObjectContext) throws -> [(String, String)] {
        let request = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
        return try context.fetch(request)
            .map { ($0.transactionId ?? "", $0.subcategoryId ?? "") }
            .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    }

    // MARK: - Reads

    @Test("Subcategories of a category come in the user's order, others excluded")
    func readsOneCategoryInOrder() throws {
        let context = try makeContext()
        seedSubcategory("s-coffee", name: "Кофе", in: context)
        seedSubcategory("s-lunch", name: "Обеды", in: context)
        seedSubcategory("s-fuel", name: "Бензин", in: context)
        seedCategoryLink(category: "c-food", subcategory: "s-lunch", order: 1, in: context)
        seedCategoryLink(category: "c-food", subcategory: "s-coffee", order: 0, in: context)
        seedCategoryLink(category: "c-car", subcategory: "s-fuel", order: 0, in: context)
        try context.save()

        let result = IntentSubcategoryStore.subcategories(ofCategoryIds: ["c-food"], context: context)
        #expect(result.map(\.id) == ["s-coffee", "s-lunch"])
        #expect(result.map(\.name) == ["Кофе", "Обеды"])
    }

    @Test("A subcategory shared by two categories is listed once")
    func sharedSubcategoryIsListedOnce() throws {
        let context = try makeContext()
        seedSubcategory("s-gift", name: "Подарки", in: context)
        seedSubcategory("s-fuel", name: "Бензин", in: context)
        seedCategoryLink(category: "c-family", subcategory: "s-gift", order: 0, in: context)
        seedCategoryLink(category: "c-car", subcategory: "s-fuel", order: 0, in: context)
        seedCategoryLink(category: "c-car", subcategory: "s-gift", order: 1, in: context)
        try context.save()

        let result = IntentSubcategoryStore.subcategories(ofCategoryIds: ["c-family", "c-car"], context: context)
        #expect(result.map(\.id) == ["s-gift", "s-fuel"])
    }

    @Test("A category without subcategories yields nothing")
    func emptyCategory() throws {
        let context = try makeContext()
        #expect(IntentSubcategoryStore.subcategories(ofCategoryIds: ["c-none"], context: context).isEmpty)
        #expect(IntentSubcategoryStore.subcategories(ofCategoryIds: [], context: context).isEmpty)
    }

    // MARK: - Writes

    @Test("Adding links keeps every other transaction's links")
    func addLinksKeepsOtherLinks() throws {
        let context = try makeContext()
        seedTransactionLink(transaction: "t-old", subcategory: "s-coffee", in: context)
        seedTransactionLink(transaction: "t-older", subcategory: "s-lunch", in: context)
        try context.save()

        IntentSubcategoryStore.addLinks(transactionId: "t-new", subcategoryIds: ["s-coffee"], context: context)

        #expect(!context.hasChanges)
        let links = try transactionLinks(in: context)
        #expect(links.count == 3)
        #expect(links.contains { $0 == ("t-new", "s-coffee") })
        #expect(links.contains { $0 == ("t-old", "s-coffee") })
        #expect(links.contains { $0 == ("t-older", "s-lunch") })
    }

    @Test("Nothing is written without a transaction id or subcategories")
    func addLinksIgnoresEmptyInput() throws {
        let context = try makeContext()
        IntentSubcategoryStore.addLinks(transactionId: "", subcategoryIds: ["s-coffee"], context: context)
        IntentSubcategoryStore.addLinks(transactionId: "t-new", subcategoryIds: [], context: context)
        #expect(try transactionLinks(in: context).isEmpty)
    }
}
