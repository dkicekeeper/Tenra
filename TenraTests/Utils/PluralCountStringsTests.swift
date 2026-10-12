//
//  PluralCountStringsTests.swift
//  TenraTests
//
//  Count subtitles ("3 accounts", "1 active loan") take their plural forms from
//  Localizable.stringsdict and are formatted with String(format: NSLocalizedString(...), n),
//  as the Finances cards do. A plain Localizable.strings value can't agree with the number:
//  the store screenshots showed "1 активных кредитов" and "1 active loans".
//

import Testing
import Foundation
@testable import Tenra

struct PluralCountStringsTests {

    /// The app bundle's localization for `language`: the test host is the app.
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func count(_ key: String, _ value: Int, in language: String) throws -> String {
        let format = NSLocalizedString(key, bundle: try bundle(language), comment: "")
        return String(format: format, locale: Locale(identifier: language), value)
    }

    @Test("Russian picks one, few and many")
    func russian() throws {
        #expect(try count("loan.activeCount", 1, in: "ru") == "1 активный кредит")
        #expect(try count("loan.activeCount", 3, in: "ru") == "3 активных кредита")
        #expect(try count("loan.activeCount", 5, in: "ru") == "5 активных кредитов")
        #expect(try count("finances.accounts.count", 3, in: "ru") == "3 счёта")
        #expect(try count("finances.deposits.count", 1, in: "ru") == "1 депозит")
        #expect(try count("finances.subcategories.linkedTo", 1, in: "ru") == "В 1 категории")
    }

    @Test("English picks one and other")
    func english() throws {
        #expect(try count("loan.activeCount", 1, in: "en") == "1 active loan")
        #expect(try count("loan.activeCount", 2, in: "en") == "2 active loans")
        #expect(try count("subcategory.usageCount", 1, in: "en") == "Used 1 time")
        #expect(try count("finances.categories.count", 12, in: "en") == "12 categories")
    }

    @Test("Japanese keeps its single form")
    func japanese() throws {
        #expect(try count("loan.activeCount", 1, in: "ja") == "1件の有効なローン")
    }
}
