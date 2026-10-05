//
//  MerchantCategoryMemoryTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct MerchantCategoryMemoryTests {

    private let groceries = CustomCategory(id: "cat-groceries", name: "Продукты", colorHex: "#00AA00", type: .expense)
    private let cafe = CustomCategory(id: "cat-cafe", name: "Кафе", colorHex: "#AA0000", type: .expense)
    private let salary = CustomCategory(id: "cat-salary", name: "Зарплата", colorHex: "#0000AA", type: .income)

    private var categories: [CustomCategory] { [groceries, cafe, salary] }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "merchant.memory.\(UUID().uuidString)")!
    }

    @Test("An unknown merchant has no category")
    func unknownMerchant() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        #expect(memory.category(forMerchant: "Corner Bakery", in: categories) == nil)
    }

    @Test("A remembered merchant matches despite store numbers, case and punctuation")
    func matchesNormalizedMerchant() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, forMerchant: "GREENMART CASH&CARRY 123")

        #expect(memory.category(forMerchant: "Greenmart Cash&Carry 456", in: categories)?.id == groceries.id)
        #expect(memory.category(forMerchant: "Greenmart Express", in: categories) == nil)
    }

    @Test("The latest choice wins")
    func latestChoiceWins() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, forMerchant: "Corner Bakery")
        memory.remember(categoryId: cafe.id, forMerchant: "Corner Bakery")

        #expect(memory.category(forMerchant: "Corner Bakery", in: categories)?.id == cafe.id)
    }

    @Test("A renamed category is still found by id")
    func survivesRename() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: cafe.id, forMerchant: "Corner Bakery")

        var renamed = cafe
        renamed.name = "Кафе и рестораны"
        #expect(memory.category(forMerchant: "Corner Bakery", in: [groceries, renamed])?.name == "Кафе и рестораны")
    }

    @Test("A deleted category reads as unknown, so the user is asked again")
    func deletedCategoryIsUnknown() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: cafe.id, forMerchant: "Corner Bakery")

        #expect(memory.category(forMerchant: "Corner Bakery", in: [groceries, salary]) == nil)
    }

    @Test("Only expense categories are returned")
    func expenseOnly() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: salary.id, forMerchant: "Acme Payroll")

        #expect(memory.category(forMerchant: "Acme Payroll", in: categories) == nil)
    }

    @Test("Merchants with too little text are never remembered")
    func tooShortMerchant() {
        #expect(MerchantCategoryMemory.key(forMerchant: "") == nil)
        #expect(MerchantCategoryMemory.key(forMerchant: "12345") == nil)
        #expect(MerchantCategoryMemory.key(forMerchant: "AB 77") == nil)

        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, forMerchant: "AB 77")
        #expect(memory.category(forMerchant: "AB 77", in: categories) == nil)
    }

    @Test("An in-app correction updates a remembered merchant only")
    func correctionTouchesKnownMerchantsOnly() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.correct(categoryId: cafe.id, subcategoryIds: ["sub-pastry"], forMerchant: "Corner Bakery")
        #expect(memory.category(forMerchant: "Corner Bakery", in: categories) == nil)
        #expect(memory.subcategoryIds(forMerchant: "Corner Bakery") == nil)

        memory.remember(categoryId: groceries.id, forMerchant: "Corner Bakery")
        memory.correct(categoryId: cafe.id, subcategoryIds: ["sub-pastry"], forMerchant: "CORNER BAKERY 2")
        #expect(memory.category(forMerchant: "Corner Bakery", in: categories)?.id == cafe.id)
        #expect(memory.subcategoryIds(forMerchant: "Corner Bakery") == ["sub-pastry"])
    }

    // MARK: - Subcategories

    @Test("A subcategory is remembered with the category")
    func remembersSubcategory() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, subcategoryIds: ["sub-veg"], forMerchant: "Greenmart 12")

        #expect(memory.subcategoryIds(forMerchant: "GREENMART 7") == ["sub-veg"])
    }

    @Test("Choosing no subcategory is remembered as a decision, not as unknown")
    func remembersNoSubcategory() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, subcategoryIds: [], forMerchant: "Greenmart")
        #expect(memory.subcategoryIds(forMerchant: "Greenmart") == [])

        memory.remember(categoryId: cafe.id, forMerchant: "Corner Bakery")
        #expect(memory.subcategoryIds(forMerchant: "Corner Bakery") == nil)
    }

    @Test("A category passed alone keeps the subcategory chosen for the same category")
    func categoryAloneKeepsSubcategory() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, subcategoryIds: ["sub-veg"], forMerchant: "Greenmart")
        memory.remember(categoryId: groceries.id, forMerchant: "Greenmart")

        #expect(memory.subcategoryIds(forMerchant: "Greenmart") == ["sub-veg"])
    }

    @Test("A different category drops the old category's subcategory")
    func newCategoryDropsSubcategory() {
        let memory = MerchantCategoryMemory(defaults: makeDefaults())
        memory.remember(categoryId: groceries.id, subcategoryIds: ["sub-veg"], forMerchant: "Greenmart")
        memory.remember(categoryId: cafe.id, forMerchant: "Greenmart")

        #expect(memory.category(forMerchant: "Greenmart", in: categories)?.id == cafe.id)
        #expect(memory.subcategoryIds(forMerchant: "Greenmart") == nil)
    }

    @Test("Choices survive a new instance over the same defaults")
    func persists() {
        let defaults = makeDefaults()
        MerchantCategoryMemory(defaults: defaults)
            .remember(categoryId: groceries.id, subcategoryIds: ["sub-veg"], forMerchant: "Corner Bakery")

        let reloaded = MerchantCategoryMemory(defaults: defaults)
        #expect(reloaded.category(forMerchant: "Corner Bakery", in: categories)?.id == groceries.id)
        #expect(reloaded.subcategoryIds(forMerchant: "Corner Bakery") == ["sub-veg"])

        reloaded.reset()
        #expect(MerchantCategoryMemory(defaults: defaults).category(forMerchant: "Corner Bakery", in: categories) == nil)
    }
}
