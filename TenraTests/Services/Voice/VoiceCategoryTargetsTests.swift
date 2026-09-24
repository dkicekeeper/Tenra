//
//  VoiceCategoryTargetsTests.swift
//  TenraTests
//
//  Voice keywords map to a category NAME that must exist among the user's
//  categories, or the operation falls back to "Other". Onboarding creates the
//  preset categories, so every map target must equal a preset name in some
//  locale. The Russian map used to target "Еда" and "Покупки", which no preset
//  creates, so "кофе" and "обед" landed in "Прочее".
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct VoiceCategoryTargetsTests {

    private static let locales = ["en", "ru", "de", "es", "fr", "tr", "pt-BR", "it", "uk", "ja", "ko"]

    private static func presetNames() -> Set<String> {
        let keys = Set((CategoryPreset.defaultExpense + CategoryPreset.defaultIncome).map(\.nameKey))
        var names = Set<String>()
        for locale in locales {
            for bundle in [Bundle.main, Bundle(for: CategoriesViewModel.self)] {
                guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                      let table = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
                for key in keys {
                    if let value = table[key] { names.insert(value) }
                }
                break
            }
        }
        return names
    }

    @Test func everyKeywordTargetIsAnOnboardingPreset() {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "voice_targets.\(UUID().uuidString)")!)
        let categoriesVM = CategoriesViewModel(repository: repo)
        let accountsVM = AccountsViewModel(repository: repo)
        let transactionsVM = TransactionsViewModel(repository: repo)
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesVM,
            accountsViewModel: accountsVM,
            transactionsViewModel: transactionsVM
        )

        let presets = Self.presetNames()
        #expect(presets.count > 100, "preset names were not loaded from the bundle")

        let orphans = parser.categoryMapTargets.subtracting(presets).sorted()
        #expect(orphans.isEmpty, "voice keywords point at categories onboarding never creates: \(orphans)")
    }
}
