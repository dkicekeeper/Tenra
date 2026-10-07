//
//  SubcategoryAppEntity.swift
//  Tenra
//
//  Subcategory picker for the Shortcuts app and for AddExpenseIntent's
//  one-time question about a new merchant. Only subcategories of expense
//  categories are suggested: AddExpenseIntent creates expenses.
//
//  Read from CoreData through IntentSubcategoryStore, because a process
//  launched only for an intent has no subcategories in memory.
//

import AppIntents

struct SubcategoryAppEntity: AppEntity {

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "intent.entity.subcategory"
    )

    static var defaultQuery = SubcategoryEntityQuery()

    /// The "no subcategory" answer to the one-time question. Not a real
    /// subcategory id: TransactionStore ids are UUID strings.
    static let noneId = "none"

    static var none: SubcategoryAppEntity {
        SubcategoryAppEntity(id: noneId, name: String(localized: "intent.entity.subcategory.none"))
    }

    var id: String
    var name: String

    var isNone: Bool { id == Self.noneId }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SubcategoryEntityQuery: EntityQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [SubcategoryAppEntity] {
        let all = [SubcategoryAppEntity.none] + (try await suggestedEntities())
        return all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SubcategoryAppEntity] {
        let services = try await IntentEnvironment.shared.services()
        let expenseCategoryIds = services.categories.customCategories
            .filter { $0.type == .expense }
            .map(\.id)
        return IntentSubcategoryStore
            .subcategories(ofCategoryIds: expenseCategoryIds, context: CoreDataStack.shared.viewContext)
            .map { SubcategoryAppEntity(id: $0.id, name: $0.name) }
    }
}
