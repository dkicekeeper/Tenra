//
//  CategoryEntityRoundTripTests.swift
//  AIFinanceManagerTests
//
//  CoreData round-trip tests for CustomCategoryEntity:
//    - Scalar fields (id, name, type, colorHex)
//    - Budget fields (budgetAmount, budgetPeriod, budgetResetDay)
//    - Income category type preservation
//    - budgetAmount == 0.0 → nil on decode
//    - Multiple categories maintain unique IDs
//
//  Uses an isolated in-memory NSPersistentContainer.
//  TEST-08
//

import Testing
import CoreData
import Foundation
@testable import AIFinanceManager

@Suite("CategoryEntity Round-Trip Tests", .serialized)
struct CategoryEntityRoundTripTests {

    // MARK: - In-Memory Container

    private func makeContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "AIFinanceManager")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        desc.url = URL(string: "memory://\(UUID().uuidString)")
        desc.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }
        return container
    }

    // MARK: - Category Factory

    private func makeCategory(
        id: String = UUID().uuidString,
        name: String = "Food",
        colorHex: String = "#FF5733",
        type: TransactionType = .expense,
        budgetAmount: Double? = nil,
        budgetPeriod: CustomCategory.BudgetPeriod = .monthly,
        budgetResetDay: Int = 1
    ) -> CustomCategory {
        CustomCategory(
            id: id,
            name: name,
            iconSource: .sfSymbol("fork.knife"),
            colorHex: colorHex,
            type: type,
            budgetAmount: budgetAmount,
            budgetPeriod: budgetPeriod,
            budgetResetDay: budgetResetDay
        )
    }

    // MARK: - Test A: Scalar fields

    @Test("Test A: Scalar fields round-trip (id, name, type, colorHex)")
    func testScalarFieldsRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(id: "cat-1", name: "Groceries", colorHex: "#2ECC71", type: .expense)

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        #expect(result.id == "cat-1")
        #expect(result.name == "Groceries")
        #expect(result.colorHex == "#2ECC71")
        #expect(result.type == .expense)
    }

    // MARK: - Test B: Income type preserved

    @Test("Test B: Income type category survives round-trip")
    func testIncomeTypeRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(name: "Salary", type: .income)

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        #expect(result.type == .income)
    }

    // MARK: - Test C: Budget fields

    @Test("Test C: Budget fields round-trip (amount, period, resetDay)")
    func testBudgetFieldsRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(
            name: "Entertainment",
            budgetAmount: 50_000,
            budgetPeriod: .monthly,
            budgetResetDay: 15
        )

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        #expect(result.budgetAmount == 50_000)
        #expect(result.budgetPeriod == .monthly)
        #expect(result.budgetResetDay == 15)
    }

    @Test("Test D: Budget period .weekly survives round-trip")
    func testWeeklyBudgetPeriod() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(budgetAmount: 10_000, budgetPeriod: .weekly)

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        #expect(result.budgetPeriod == .weekly)
    }

    // MARK: - Test E: nil budget amount (0.0 stored → nil on decode)

    @Test("Test E: Category without budget — budgetAmount is nil after round-trip")
    func testNoBudgetAmountIsNil() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(budgetAmount: nil)

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        #expect(result.budgetAmount == nil,
                "budgetAmount stored as 0.0 must decode as nil (0.0 == nil sentinel)")
    }

    // MARK: - Test F: iconName defaults

    @Test("Test F: IconSource with sfSymbol name stored and retrieved as iconName")
    func testIconNameRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(name: "Transport")

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        guard case .sfSymbol(let symbolName) = result.iconSource else {
            Issue.record("Expected .sfSymbol iconSource, got \(result.iconSource)")
            return
        }
        #expect(!symbolName.isEmpty, "sfSymbol name must not be empty")
    }

    // MARK: - Test G: Multiple categories

    @Test("Test G: Multiple categories maintain unique IDs and correct names")
    func testMultipleCategoriesUniqueIds() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let names = ["Food", "Transport", "Healthcare", "Entertainment", "Salary"]
        let categories = names.enumerated().map { i, name in
            makeCategory(id: "cat-\(i)", name: name)
        }

        ctx.performAndWait {
            for cat in categories { _ = CustomCategoryEntity.from(cat, context: ctx) }
            try? ctx.save()
            ctx.reset()
        }

        var fetchedNames: Set<String> = []
        ctx.performAndWait {
            let all = (try? ctx.fetch(NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity"))) ?? []
            fetchedNames = Set(all.compactMap(\.name))
        }

        #expect(fetchedNames.count == 5)
        for name in names {
            #expect(fetchedNames.contains(name))
        }
    }

    // MARK: - Test H: Yearly budget period

    @Test("Test H: Budget period .yearly survives round-trip")
    func testYearlyBudgetPeriod() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let category = makeCategory(budgetAmount: 500_000, budgetPeriod: .yearly, budgetResetDay: 1)

        ctx.performAndWait {
            _ = CustomCategoryEntity.from(category, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: CustomCategory?
        ctx.performAndWait {
            let req = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            req.predicate = NSPredicate(format: "id == %@", category.id)
            loaded = (try? ctx.fetch(req))?.first?.toCustomCategory()
        }

        let result = try #require(loaded)
        #expect(result.budgetPeriod == .yearly)
        #expect(result.budgetAmount == 500_000)
    }
}
