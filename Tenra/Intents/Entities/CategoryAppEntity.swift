//
//  CategoryAppEntity.swift
//  Tenra
//
//  Category picker for the Shortcuts app. Only expense categories are
//  suggested: AddExpenseIntent creates expenses.
//

import AppIntents

struct CategoryAppEntity: AppEntity {

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "intent.entity.category"
    )

    static var defaultQuery = CategoryEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CategoryEntityQuery: EntityQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [CategoryAppEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryAppEntity] {
        let services = await IntentEnvironment.shared.services()
        return services.categories.customCategories
            .filter { $0.type == .expense }
            .map { CategoryAppEntity(id: $0.id, name: $0.name) }
    }
}
