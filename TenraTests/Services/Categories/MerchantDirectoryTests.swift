//
//  MerchantDirectoryTests.swift
//  TenraTests
//
//  Pins the merchants "Combine points" and the form's merchant picker list: how often each
//  one is paid, and the categories and subcategories its payments carry for the search.
//

import Testing
import Foundation
@testable import Tenra

struct MerchantDirectoryTests {

    private func tx(_ id: String, _ description: String, category: String, subcategory: String? = nil) -> Transaction {
        Transaction(id: id, date: "2026-10-30", description: description, amount: 2_500, currency: "KZT",
                    type: .expense, category: category, subcategory: subcategory, accountId: "a1")
    }

    @Test("Each merchant carries its payments' categories and subcategories, normalized")
    func tags() {
        let history = [
            tx("t1", "YANDEX.GO", category: "Транспорт"),
            tx("t2", "YANDEX.GO 2", category: "Транспорт"),
            tx("t3", "GREENMART", category: "Продукты", subcategory: "Овощи")
        ]
        let entries = MerchantDirectory.entries(
            in: history,
            excluding: [],
            like: "",
            subcategoryIds: ["t1": ["s-taxi"], "t2": ["s-taxi", "s-missing"]],
            subcategoryNames: ["s-taxi": "Такси"]
        )
        let yandex = entries.first { $0.id == "yandex go" }
        #expect(yandex?.count == 2)
        #expect(yandex?.tags == ["такси", "транспорт"])
        let greenmart = entries.first { $0.id == "greenmart" }
        #expect(greenmart?.tags == ["овощи", "продукты"])
    }
}
