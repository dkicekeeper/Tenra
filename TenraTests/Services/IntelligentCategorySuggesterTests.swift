//
//  IntelligentCategorySuggesterTests.swift
//  TenraTests
//
//  The deterministic half of the Apple Intelligence category tier: which merchants
//  are asked (deduplicated, per type, in batches) and how answers map back to
//  rows. The model call itself is device-dependent and not unit-testable; its
//  answer schema only allows the user's categories or NONE.
//

import Testing
@testable import Tenra

struct IntelligentCategorySuggesterTests {

    private typealias Item = IntelligentCategorySuggester.Item

    private let categories: [TransactionType: [String]] = [
        .expense: ["Кафе и рестораны", "Продукты", "Транспорт"],
        .income: ["Зарплата"]
    ]

    @Test func sameMerchantIsAskedOnce() {
        let items = [
            Item(id: "1", description: "WOLT.COM ALMATY KZ", type: .expense),
            Item(id: "2", description: "wolt.com  almaty kz", type: .expense),
            Item(id: "3", description: "YANDEX.GO ALMATY KZ", type: .expense),
            Item(id: "4", description: "AB", type: .expense)            // too short to mean anything
        ]
        let batches = IntelligentCategorySuggester.batches(for: items, categories: categories)
        #expect(batches == [
            IntelligentCategorySuggester.Batch(
                type: .expense,
                merchants: ["WOLT.COM ALMATY KZ", "YANDEX.GO ALMATY KZ"],
                categories: ["Кафе и рестораны", "Продукты", "Транспорт"]
            )
        ])
    }

    @Test func typesAreAskedSeparatelyAndLongListsAreSplit() {
        var items = (1...16).map { Item(id: "e\($0)", description: "SHOP NUMBER \(String(repeating: "X", count: $0))", type: .expense) }
        items.append(Item(id: "i1", description: "ТОО Работа", type: .income))
        items.append(Item(id: "t1", description: "Перевод", type: .internalTransfer))   // no categories: skipped

        let batches = IntelligentCategorySuggester.batches(for: items, categories: categories)
        #expect(batches.map(\.type) == [.expense, .expense, .income])
        #expect(batches.map(\.merchants.count) == [15, 1, 1])
        #expect(batches[2].categories == ["Зарплата"])
    }

    @Test func answersReachEveryRowOfTheMerchantAndOnlyRealCategories() {
        let items = [
            Item(id: "1", description: "WOLT.COM ALMATY KZ", type: .expense),
            Item(id: "2", description: "WOLT.COM ALMATY KZ", type: .expense),
            Item(id: "3", description: "APM AOF BORALDAJ KZ", type: .expense),
            Item(id: "4", description: "Перевод · Асан Б.", type: .expense),
            Item(id: "5", description: "WOLT.COM ALMATY KZ", type: .income)
        ]
        let answers = [
            "WOLT.COM ALMATY KZ": "Кафе и рестораны",
            "APM AOF BORALDAJ KZ": "Одежда",                                     // not one of the user's
            "Перевод · Асан Б.": IntelligentCategorySuggester.noneChoice
        ]
        let assigned = IntelligentCategorySuggester.assign(
            answers, type: .expense, categories: categories[.expense]!, to: items)
        #expect(assigned == ["1": "Кафе и рестораны", "2": "Кафе и рестораны"])
    }

    @Test func promptListsTheCategoriesAndNumbersTheRows() {
        let prompt = IntelligentCategorySuggester.prompt(for: IntelligentCategorySuggester.Batch(
            type: .expense, merchants: ["WOLT.COM ALMATY KZ", "YANDEX.GO"], categories: ["Кафе", "Транспорт"]))
        #expect(prompt.contains("Allowed spending categories: Кафе, Транспорт"))
        #expect(prompt.contains("1. WOLT.COM ALMATY KZ\n2. YANDEX.GO"))
    }
}
