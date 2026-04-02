//
//  CategoryRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Category-specific data persistence operations

import Foundation
import CoreData
import os

/// Protocol for category repository operations
protocol CategoryRepositoryProtocol: Sendable {
    nonisolated func loadCategories() -> [CustomCategory]
    nonisolated func saveCategories(_ categories: [CustomCategory])
    nonisolated func saveCategoriesSync(_ categories: [CustomCategory]) throws
    nonisolated func loadCategoryRules() -> [CategoryRule]
    nonisolated func saveCategoryRules(_ rules: [CategoryRule])
    nonisolated func loadSubcategories() -> [Subcategory]
    nonisolated func saveSubcategories(_ subcategories: [Subcategory])
    nonisolated func saveSubcategoriesSync(_ subcategories: [Subcategory]) throws
    nonisolated func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink]
    nonisolated func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink])
    nonisolated func saveCategorySubcategoryLinksSync(_ links: [CategorySubcategoryLink]) throws
    nonisolated func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink]
    nonisolated func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink])
    nonisolated func saveTransactionSubcategoryLinksSync(_ links: [TransactionSubcategoryLink]) throws
    nonisolated func loadAggregates(year: Int16?, month: Int16?, limit: Int?) -> [CategoryAggregate]
    nonisolated func saveAggregates(_ aggregates: [CategoryAggregate])
}

/// CoreData implementation of CategoryRepositoryProtocol
nonisolated final class CategoryRepository: CategoryRepositoryProtocol, @unchecked Sendable {

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CategoryRepository")

    private let stack: CoreDataStack
    private let saveCoordinator: CoreDataSaveCoordinator
    private let userDefaultsRepository: UserDefaultsRepository

    init(
        stack: CoreDataStack = .shared,
        saveCoordinator: CoreDataSaveCoordinator,
        userDefaultsRepository: UserDefaultsRepository = UserDefaultsRepository()
    ) {
        self.stack = stack
        self.saveCoordinator = saveCoordinator
        self.userDefaultsRepository = userDefaultsRepository
    }

    // MARK: - Categories

    func loadCategories() -> [CustomCategory] {
        PerformanceProfiler.start("CategoryRepository.loadCategories")

        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var categories: [CustomCategory] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.fetchBatchSize = 100

            do {
                let entities = try bgContext.fetch(request)
                categories = entities.map { $0.toCustomCategory() }
            } catch {
                loadError = error
            }
        }

        PerformanceProfiler.end("CategoryRepository.loadCategories")

        if loadError != nil {
            // Fallback to UserDefaults if Core Data fetch failed
            return userDefaultsRepository.loadCategories()
        }
        return categories
    }

    func saveCategories(_ categories: [CustomCategory]) {

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("CategoryRepository.saveCategories")

            do {
                try await self.saveCoordinator.performSave(operation: "saveCategories") { context in
                    try self.saveCategoriesInternal(categories, context: context)
                }

                PerformanceProfiler.end("CategoryRepository.saveCategories")

            } catch {
                PerformanceProfiler.end("CategoryRepository.saveCategories")
            }
        }
    }

    func saveCategoriesSync(_ categories: [CustomCategory]) throws {
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try context.performAndWait {
            try saveCategoriesInternal(categories, context: context)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    // MARK: - Category Rules

    func loadCategoryRules() -> [CategoryRule] {
        let bgContext = stack.newBackgroundContext()
        var rules: [CategoryRule] = []
        bgContext.performAndWait {
            let request = NSFetchRequest<CategoryRuleEntity>(entityName: "CategoryRuleEntity")
            request.predicate = NSPredicate(format: "isEnabled == YES")
            request.fetchBatchSize = 100
            if let entities = try? bgContext.fetch(request) {
                rules = entities.map { $0.toCategoryRule() }
            }
        }
        if rules.isEmpty {
            return userDefaultsRepository.loadCategoryRules()
        }
        return rules
    }

    func saveCategoryRules(_ rules: [CategoryRule]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let bgContext = self.stack.newBackgroundContext()
            bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            await bgContext.perform {
                do {
                    // 1. Batch delete all existing rules
                    let deleteRequest = NSBatchDeleteRequest(
                        fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "CategoryRuleEntity")
                    )
                    deleteRequest.resultType = .resultTypeObjectIDs
                    let deleteResult = try bgContext.execute(deleteRequest) as? NSBatchDeleteResult
                    let deletedIDs = deleteResult?.result as? [NSManagedObjectID] ?? []
                    if !deletedIDs.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            NSManagedObjectContext.mergeChanges(
                                fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                                into: [self.stack.viewContext]
                            )
                        }
                    }
                    bgContext.reset()

                    // 2. Create new rules
                    for rule in rules {
                        _ = CategoryRuleEntity.from(rule, context: bgContext)
                    }
                    if bgContext.hasChanges {
                        try bgContext.save()
                    }
                } catch {
                    Self.logger.error("saveCategoryRules failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Subcategories

    func loadSubcategories() -> [Subcategory] {
        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var subcategories: [Subcategory] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.fetchBatchSize = 200

            do {
                let entities = try bgContext.fetch(request)
                subcategories = entities.map { $0.toSubcategory() }
            } catch {
                loadError = error
            }
        }

        if loadError != nil {
            return userDefaultsRepository.loadSubcategories()
        }
        return subcategories
    }

    func saveSubcategories(_ subcategories: [Subcategory]) {

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    try self.saveSubcategoriesInternal(subcategories, context: context)

                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    Self.logger.error("saveSubcategories failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func saveSubcategoriesSync(_ subcategories: [Subcategory]) throws {
        PerformanceProfiler.start("CategoryRepository.saveSubcategoriesSync")

        // Use background context to avoid blocking UI
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try backgroundContext.performAndWait {
            try saveSubcategoriesInternal(subcategories, context: backgroundContext)

            // Save if there are changes
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }
        }

        PerformanceProfiler.end("CategoryRepository.saveSubcategoriesSync")
    }

    // MARK: - Category-Subcategory Links

    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var links: [CategorySubcategoryLink] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "categoryId", ascending: true)]
            request.fetchBatchSize = 200

            do {
                let entities = try bgContext.fetch(request)
                links = entities.map { $0.toCategorySubcategoryLink() }
            } catch {
                loadError = error
            }
        }

        if loadError != nil {
            return userDefaultsRepository.loadCategorySubcategoryLinks()
        }
        return links
    }

    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    try self.saveCategorySubcategoryLinksInternal(links, context: context)

                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    Self.logger.error("saveCategorySubcategoryLinks failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func saveCategorySubcategoryLinksSync(_ links: [CategorySubcategoryLink]) throws {
        PerformanceProfiler.start("CategoryRepository.saveCategorySubcategoryLinksSync")

        // Use background context to avoid blocking UI
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try backgroundContext.performAndWait {
            try saveCategorySubcategoryLinksInternal(links, context: backgroundContext)

            // Counts already calculated in internal method

            // Save if there are changes
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }
        }

        PerformanceProfiler.end("CategoryRepository.saveCategorySubcategoryLinksSync")
    }

    // MARK: - Transaction-Subcategory Links

    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var links: [TransactionSubcategoryLink] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "transactionId", ascending: true)]
            request.fetchBatchSize = 500

            do {
                let entities = try bgContext.fetch(request)
                links = entities.map { $0.toTransactionSubcategoryLink() }
            } catch {
                loadError = error
            }
        }

        if loadError != nil {
            return userDefaultsRepository.loadTransactionSubcategoryLinks()
        }
        return links
    }

    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    try self.saveTransactionSubcategoryLinksInternal(links, context: context)

                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    Self.logger.error("saveTransactionSubcategoryLinks failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func saveTransactionSubcategoryLinksSync(_ links: [TransactionSubcategoryLink]) throws {
        PerformanceProfiler.start("CategoryRepository.saveTransactionSubcategoryLinksSync")

        // Use background context to avoid blocking UI
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try backgroundContext.performAndWait {
            try saveTransactionSubcategoryLinksInternal(links, context: backgroundContext)

            // Save if there are changes
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }
        }

        PerformanceProfiler.end("CategoryRepository.saveTransactionSubcategoryLinksSync")
    }

    // MARK: - Category Aggregates

    func loadAggregates(
        year: Int16? = nil,
        month: Int16? = nil,
        limit: Int? = nil
    ) -> [CategoryAggregate] {
        let bgContext = stack.newBackgroundContext()
        var aggregates: [CategoryAggregate] = []

        bgContext.performAndWait {
            let request = CategoryAggregateEntity.fetchRequest()

            var predicates: [NSPredicate] = []

            if let year = year {
                predicates.append(NSPredicate(format: "year == %d OR year == 0", year))
                if let month = month {
                    predicates.append(NSPredicate(format: "month == %d OR month == 0", month))
                }
            }

            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }

            request.sortDescriptors = [NSSortDescriptor(key: "lastUpdated", ascending: false)]
            request.fetchBatchSize = 200

            if let limit = limit {
                request.fetchLimit = limit
            }

            if let entities = try? bgContext.fetch(request) {
                aggregates = entities.map { $0.toAggregate() }
            }
        }

        return aggregates
    }

    func saveAggregates(_ aggregates: [CategoryAggregate]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            do {
                try await self.saveCoordinator.performSave(operation: "saveAggregates") { context in
                    try self.saveAggregatesInternal(aggregates, context: context)
                }
            } catch {
                // Логировать ошибку
            }
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func saveCategoriesInternal(_ categories: [CustomCategory], context: NSManagedObjectContext) throws {
        // Caller is already inside context.perform/performAndWait — direct access is safe.
        let fetchRequest = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        let existingEntities = try context.fetch(fetchRequest)

        var existingDict: [String: CustomCategoryEntity] = [:]
        for entity in existingEntities {
            let entityId = entity.id ?? ""
            if !entityId.isEmpty && existingDict[entityId] == nil {
                existingDict[entityId] = entity
            } else if !entityId.isEmpty {
                context.delete(entity)
            }
        }

        var keptIds = Set<String>()

        for category in categories {
            keptIds.insert(category.id)

            if let existing = existingDict[category.id] {
                // Direct mutation — caller is already inside perform/performAndWait
                existing.name = category.name
                existing.type = category.type.rawValue
                if case .sfSymbol(let symbolName) = category.iconSource {
                    existing.iconName = symbolName
                } else {
                    existing.iconName = "questionmark.circle"
                }
                existing.colorHex = category.colorHex
                existing.budgetAmount = category.budgetAmount ?? 0.0
                existing.budgetPeriod = category.budgetPeriod.rawValue
                existing.budgetStartDate = category.budgetStartDate
                existing.budgetResetDay = Int64(category.budgetResetDay)
            } else {
                _ = CustomCategoryEntity.from(category, context: context)
            }
        }

        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }

    private nonisolated func saveSubcategoriesInternal(_ subcategories: [Subcategory], context: NSManagedObjectContext) throws {
        // Caller is already inside context.perform/performAndWait — direct access is safe.
        let fetchRequest = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
        let existingEntities = try context.fetch(fetchRequest)

        var existingDict: [String: SubcategoryEntity] = [:]
        for entity in existingEntities {
            let entityId = entity.id ?? ""
            if !entityId.isEmpty && existingDict[entityId] == nil {
                existingDict[entityId] = entity
            } else if !entityId.isEmpty {
                context.delete(entity)
            }
        }

        var keptIds = Set<String>()

        for subcategory in subcategories {
            keptIds.insert(subcategory.id)

            if let existing = existingDict[subcategory.id] {
                existing.name = subcategory.name
            } else {
                _ = SubcategoryEntity.from(subcategory, context: context)
            }
        }

        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }

    private nonisolated func saveCategorySubcategoryLinksInternal(_ links: [CategorySubcategoryLink], context: NSManagedObjectContext) throws {
        // Caller is already inside context.perform/performAndWait — direct access is safe.
        let fetchRequest = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
        let existingEntities = try context.fetch(fetchRequest)

        var existingDict: [String: CategorySubcategoryLinkEntity] = [:]
        for entity in existingEntities {
            let entityId = entity.id ?? ""
            if !entityId.isEmpty && existingDict[entityId] == nil {
                existingDict[entityId] = entity
            } else if !entityId.isEmpty {
                context.delete(entity)
            }
        }

        var keptIds = Set<String>()

        // Update or create links
        for link in links {
            keptIds.insert(link.id)

            if let existing = existingDict[link.id] {
                // Direct mutation — caller is already inside perform/performAndWait
                existing.categoryId = link.categoryId
                existing.subcategoryId = link.subcategoryId
            } else {
                // Create new
                _ = CategorySubcategoryLinkEntity.from(link, context: context)
            }
        }

        // Delete links that no longer exist
        for entity in existingEntities {
            let entityId = entity.id
            if let id = entityId, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }

    private nonisolated func saveTransactionSubcategoryLinksInternal(_ links: [TransactionSubcategoryLink], context: NSManagedObjectContext) throws {
        // Fetch all existing links
        let fetchRequest = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely
        var existingDict: [String: TransactionSubcategoryLinkEntity] = [:]
        for entity in existingEntities {
            let entityId = entity.id ?? ""
            if !entityId.isEmpty && existingDict[entityId] == nil {
                existingDict[entityId] = entity
            } else if !entityId.isEmpty {
                context.delete(entity)
            }
        }

        var keptIds = Set<String>()

        // Update or create links
        for link in links {
            keptIds.insert(link.id)

            if let existing = existingDict[link.id] {
                // Direct mutation — caller is already inside perform/performAndWait
                existing.transactionId = link.transactionId
                existing.subcategoryId = link.subcategoryId
            } else {
                // Create new
                _ = TransactionSubcategoryLinkEntity.from(link, context: context)
            }
        }

        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }

    private nonisolated func saveAggregatesInternal(_ aggregates: [CategoryAggregate], context: NSManagedObjectContext) throws {
        // Caller is already inside save coordinator's context.perform — direct access is safe.
        let fetchRequest = NSFetchRequest<CategoryAggregateEntity>(entityName: "CategoryAggregateEntity")
        let existingEntities = try context.fetch(fetchRequest)

        var existingDict: [String: CategoryAggregateEntity] = [:]
        for entity in existingEntities {
            if let id = entity.id {
                existingDict[id] = entity
            }
        }

        var keptIds = Set<String>()

        // Обновить или создать агрегаты
        for aggregate in aggregates {
            keptIds.insert(aggregate.id)

            if let existing = existingDict[aggregate.id] {
                // Direct mutation — caller is already inside save coordinator's context.perform
                existing.categoryName = aggregate.categoryName
                existing.subcategoryName = aggregate.subcategoryName
                existing.year = aggregate.year
                existing.month = aggregate.month
                existing.totalAmount = aggregate.totalAmount
                existing.transactionCount = aggregate.transactionCount
                existing.currency = aggregate.currency
                existing.lastUpdated = Date()
                existing.lastTransactionDate = aggregate.lastTransactionDate
            } else {
                // Создать новый
                _ = CategoryAggregateEntity.from(aggregate, context: context)
            }
        }

        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }
}
