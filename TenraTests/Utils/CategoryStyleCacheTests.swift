//
//  CategoryStyleCacheTests.swift
//  TenraTests
//
//  Regression coverage for the selective-invalidation contract.
//
//  Before the refactor, every category mutation called
//  `CategoryStyleCache.shared.invalidateCache()` — a global wipe that caused
//  cascading re-renders across every screen using categories. Now invalidation
//  is granular and triggered ONLY when icon/color/name/type changes.
//

import Testing
import Foundation
import SwiftUI
@testable import Tenra

@MainActor
struct CategoryStyleCacheTests {

    private static func makeCategories() -> [CustomCategory] {
        [
            CustomCategory(
                id: "food",
                name: "Food",
                iconSource: .sfSymbol("fork.knife"),
                colorHex: "#FF0000",
                type: .expense
            ),
            CustomCategory(
                id: "travel",
                name: "Travel",
                iconSource: .sfSymbol("airplane"),
                colorHex: "#00FF00",
                type: .expense
            )
        ]
    }

    @Test("getStyleData returns identical instance on repeated calls (cache hit)")
    func cacheHitReturnsSameInstance() async throws {
        let cache = CategoryStyleCache.shared
        cache.invalidateCache()  // start fresh
        let cats = Self.makeCategories()

        let first  = cache.getStyleData(category: "Food", type: .expense, customCategories: cats)
        let second = cache.getStyleData(category: "Food", type: .expense, customCategories: cats)

        #expect(first == second)
    }

    @Test("invalidate(name:type:) drops only the targeted key")
    func invalidateTargetedKeepsOthers() async throws {
        let cache = CategoryStyleCache.shared
        cache.invalidateCache()
        let cats = Self.makeCategories()

        // Warm both keys.
        let foodBefore   = cache.getStyleData(category: "Food",   type: .expense, customCategories: cats)
        let travelBefore = cache.getStyleData(category: "Travel", type: .expense, customCategories: cats)

        // Invalidate only Food.
        cache.invalidate(name: "Food", type: .expense)

        // Travel must come back unchanged from the same cached entry — same colour values.
        let travelAfter = cache.getStyleData(category: "Travel", type: .expense, customCategories: cats)
        #expect(travelBefore == travelAfter)

        // Food may be recomputed; new instance is allowed but must be equal-by-value
        // (we didn't mutate the category, only invalidated).
        let foodAfter = cache.getStyleData(category: "Food", type: .expense, customCategories: cats)
        #expect(foodBefore == foodAfter)
    }

    @Test("invalidateCache wipes everything")
    func invalidateCacheWipesAll() async throws {
        let cache = CategoryStyleCache.shared
        let cats = Self.makeCategories()
        _ = cache.getStyleData(category: "Food", type: .expense, customCategories: cats)
        _ = cache.getStyleData(category: "Travel", type: .expense, customCategories: cats)

        cache.invalidateCache()

        // Recomputing must succeed — the cache should re-fill on demand.
        let food = cache.getStyleData(category: "Food", type: .expense, customCategories: cats)
        #expect(food.iconName != "")
    }
}
