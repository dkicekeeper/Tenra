//
//  CategoryPresetIncomeTests.swift
//  TenraTests
//
//  Onboarding used to create expense categories only, so a new user's first
//  income dead-ended. Pins the income presets and that every preset name key
//  is localized in all 11 locales (voice keywords target the Russian names).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryPresetIncomeTests {

    private static let locales = ["en", "ru", "de", "es", "fr", "tr", "pt-BR", "it", "uk", "ja", "ko"]

    /// Localizable.strings of one locale from the app bundle hosting the tests.
    private static func table(_ locale: String) -> [String: String] {
        let bundles = [Bundle.main, Bundle(for: CategoriesViewModel.self)]
        for bundle in bundles {
            if let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
               let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                return dict
            }
        }
        return [:]
    }

    @Test func incomePresetsExistAndAreIncome() {
        #expect(CategoryPreset.defaultIncome.count == 2)
        for preset in CategoryPreset.defaultIncome {
            #expect(preset.type == .income)
        }
    }

    @Test func incomeIdsAreUniqueAndDisjointFromExpense() {
        let income = CategoryPreset.defaultIncome.map(\.id)
        let expense = Set(CategoryPreset.defaultExpense.map(\.id))
        #expect(Set(income).count == income.count)
        #expect(Set(income).isDisjoint(with: expense))
    }

    @Test func everyPresetNameIsLocalizedInEveryLocale() {
        let keys = (CategoryPreset.defaultExpense + CategoryPreset.defaultIncome).map(\.nameKey)
        for locale in Self.locales {
            let strings = Self.table(locale)
            #expect(!strings.isEmpty, "no Localizable.strings found for \(locale)")
            for key in keys {
                #expect(strings[key]?.isEmpty == false, "\(locale) is missing \(key)")
            }
        }
    }

    @Test func russianSalaryNameMatchesVoiceTarget() {
        #expect(Self.table("ru")["onboarding.preset.salary"] == "Зарплата")
    }
}
