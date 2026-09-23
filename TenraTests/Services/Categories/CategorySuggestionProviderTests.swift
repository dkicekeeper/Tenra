//
//  CategorySuggestionProviderTests.swift
//  TenraTests
//
//  Pins the tier order for import category suggestions (history → brand →
//  voice keyword), that every candidate must resolve to one of the user's own
//  categories, and that a miss never turns into "Other".
//
//  Category names are built from the localization keys so the suite passes in
//  any simulator locale.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategorySuggestionProviderTests {

    private static func presetName(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    private static let groceries = presetName("onboarding.preset.groceries")
    private static let transport = presetName("onboarding.preset.transport")
    private static let other = String(localized: "category.other")

    private static func category(_ name: String, _ type: TransactionType = .expense) -> CustomCategory {
        CustomCategory(name: name, iconSource: .sfSymbol("tag"), colorHex: "#22c55e", type: type)
    }

    private static func tx(
        _ description: String,
        category: String = "",
        type: TransactionType = .expense,
        id: String = UUID().uuidString
    ) -> Transaction {
        Transaction(
            id: id,
            date: "2026-09-01",
            description: description,
            amount: 100,
            currency: "KZT",
            type: type,
            category: category,
            accountId: "a1"
        )
    }

    private static let noKeywords: (String) -> String? = { _ in nil }

    private static func suggest(
        _ description: String,
        type: TransactionType = .expense,
        history: [Transaction] = [],
        categories: [CustomCategory],
        keywordMatcher: (String) -> String? = noKeywords
    ) -> String? {
        CategorySuggestionProvider.suggestion(
            for: description,
            type: type,
            index: CategorySuggestionService.buildHistoryIndex(from: history),
            categories: categories,
            keywordMatcher: keywordMatcher
        )
    }

    @Test func historyBeatsBrand() {
        let categories = [Self.category(Self.groceries), Self.category("Snacks")]
        let result = Self.suggest(
            "MAGNUM",
            history: [Self.tx("MAGNUM", category: "Snacks")],
            categories: categories
        )
        #expect(result == "Snacks")
    }

    @Test func deletedHistoryCategoryFallsThroughToBrand() {
        let result = Self.suggest(
            "MAGNUM",
            history: [Self.tx("MAGNUM", category: "Snacks")],
            categories: [Self.category(Self.groceries)]
        )
        #expect(result == Self.groceries)
    }

    @Test func brandResolvesToLocalizedPresetCategory() {
        let result = Self.suggest("YANDEX.GO", categories: [Self.category(Self.transport)])
        #expect(result == Self.transport)
    }

    @Test func brandWithoutMatchingUserCategoryIsNotOther() {
        let result = Self.suggest("MAGNUM", categories: [Self.category(Self.other), Self.category(Self.transport)])
        #expect(result == nil)
    }

    @Test func keywordTierResolvesAgainstUserCategories() {
        let result = Self.suggest(
            "City taxi ride",
            categories: [Self.category("Transport")],
            keywordMatcher: { $0.lowercased().contains("taxi") ? "Transport" : nil }
        )
        #expect(result == "Transport")
    }

    @Test func incomeUsesHistoryOnly() {
        let categories = [Self.category("Salary", .income), Self.category(Self.groceries, .income)]
        #expect(Self.suggest(
            "ACME LLC",
            type: .income,
            history: [Self.tx("ACME LLC", category: "Salary", type: .income)],
            categories: categories
        ) == "Salary")
        #expect(Self.suggest(
            "MAGNUM",
            type: .income,
            categories: categories,
            keywordMatcher: { _ in "Salary" }
        ) == nil)
    }

    @Test func batchSuggestsOnlyIncomeAndExpense() async {
        let expense = Self.tx("YANDEX.GO", id: "e1")
        let transfer = Self.tx("YANDEX.GO", category: TransactionType.transferCategoryName, type: .internalTransfer, id: "t1")
        let unknown = Self.tx("Some unknown shop", id: "e2")

        let result = await CategorySuggestionProvider.suggestions(
            for: [expense, transfer, unknown],
            history: [],
            categories: [Self.category(Self.transport)],
            keywordMatcher: Self.noKeywords
        )
        #expect(result == ["e1": Self.transport])
    }
}
