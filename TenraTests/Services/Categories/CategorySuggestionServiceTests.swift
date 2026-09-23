//
//  CategorySuggestionServiceTests.swift
//  TenraTests
//
//  Pins the merchant normalization, the whole-word keyword rule, the history
//  tier (majority, then recency) and the curated brand list used to suggest
//  categories for imported statement rows and receipts.
//

import Testing
import Foundation
@testable import Tenra

struct CategorySuggestionServiceTests {

    private func tx(
        _ description: String,
        category: String,
        type: TransactionType = .expense,
        date: String = "2026-09-01"
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: description,
            amount: 100,
            currency: "KZT",
            type: type,
            category: category,
            accountId: "a1"
        )
    }

    // MARK: - Normalization

    @Test func normalizesMerchantStrings() {
        #expect(CategorySuggestionService.normalizedMerchant("YANDEX.GO") == "yandex go")
        #expect(CategorySuggestionService.normalizedMerchant("MAGNUM CASH&CARRY 123") == "magnum cash carry")
        #expect(CategorySuggestionService.normalizedMerchant("APPLE.COM/BILL") == "apple com bill")
        #expect(CategorySuggestionService.normalizedMerchant("12345") == "")
        #expect(CategorySuggestionService.normalizedMerchant("  Кофе Ёлка  ") == "кофе елка")
    }

    // MARK: - Keyword matching

    @Test func longKeywordsMatchAtWordStart() {
        #expect(CategorySuggestionService.matches(keyword: "yandex", inNormalized: "yandex go"))
        #expect(CategorySuggestionService.matches(keyword: "metro cash", inNormalized: "metro cash carry"))
        #expect(!CategorySuggestionService.matches(keyword: "andex", inNormalized: "yandex go"))
    }

    @Test func shortKeywordsMustBeWholeWords() {
        #expect(!CategorySuggestionService.matches(keyword: "abo", inNormalized: "about us"))
        #expect(CategorySuggestionService.matches(keyword: "abo", inNormalized: "abo netflix"))
        #expect(!CategorySuggestionService.matches(keyword: "cine", inNormalized: "medicine store"))
    }

    @Test func emptyKeywordNeverMatches() {
        #expect(!CategorySuggestionService.matches(keyword: "", inNormalized: "anything"))
        #expect(!CategorySuggestionService.matches(keyword: "!!", inNormalized: "anything"))
    }

    // MARK: - History tier

    @Test func historySkipsUncategorizedRows() {
        let index = CategorySuggestionService.buildHistoryIndex(from: [tx("MAGNUM", category: "")])
        #expect(index.stats.isEmpty)
        #expect(CategorySuggestionService.historyCategory(for: "MAGNUM", type: .expense, in: index) == nil)
    }

    @Test func historySkipsNonIncomeExpenseTypes() {
        let index = CategorySuggestionService.buildHistoryIndex(from: [
            tx("Transfer to savings", category: TransactionType.transferCategoryName, type: .internalTransfer)
        ])
        #expect(index.stats.isEmpty)
    }

    @Test func historyMajorityWins() {
        let index = CategorySuggestionService.buildHistoryIndex(from: [
            tx("MAGNUM", category: "Food"),
            tx("MAGNUM", category: "Food"),
            tx("MAGNUM", category: "Gifts", date: "2026-09-20")
        ])
        #expect(CategorySuggestionService.historyCategory(for: "MAGNUM", type: .expense, in: index) == "Food")
    }

    @Test func historyTieGoesToMostRecent() {
        let index = CategorySuggestionService.buildHistoryIndex(from: [
            tx("MAGNUM", category: "Food", date: "2026-08-01"),
            tx("MAGNUM", category: "Snacks", date: "2026-09-10")
        ])
        #expect(CategorySuggestionService.historyCategory(for: "MAGNUM", type: .expense, in: index) == "Snacks")
    }

    @Test func historyIsKeyedByType() {
        let index = CategorySuggestionService.buildHistoryIndex(from: [
            tx("ACME LLC", category: "Salary", type: .income)
        ])
        #expect(CategorySuggestionService.historyCategory(for: "ACME LLC", type: .expense, in: index) == nil)
        #expect(CategorySuggestionService.historyCategory(for: "ACME LLC", type: .income, in: index) == "Salary")
    }

    @Test func historyIgnoresDigitsAndPunctuation() {
        let index = CategorySuggestionService.buildHistoryIndex(from: [tx("MAGNUM 01", category: "Food")])
        #expect(CategorySuggestionService.historyCategory(for: "Magnum-02", type: .expense, in: index) == "Food")
    }

    // MARK: - Brand tier

    @Test func brandPresets() {
        #expect(CategorySuggestionService.brandPresetId(for: "YANDEX.GO") == "transport")
        #expect(CategorySuggestionService.brandPresetId(for: "APPLE.COM/BILL") == "subscriptions")
        #expect(CategorySuggestionService.brandPresetId(for: "YANDEX EDA") == "dining")
        #expect(CategorySuggestionService.brandPresetId(for: "TELE2 KAZAKHSTAN") == "utilities")
        #expect(CategorySuggestionService.brandPresetId(for: "Random shop") == nil)
    }

    @Test @MainActor func brandPresetsPointAtRealPresets() {
        let presetIds = Set(CategoryPreset.defaultExpense.map(\.id))
        for entry in CategorySuggestionService.brandPresets {
            #expect(presetIds.contains(entry.presetId), "unknown preset id \(entry.presetId) for \(entry.keyword)")
        }
    }
}
