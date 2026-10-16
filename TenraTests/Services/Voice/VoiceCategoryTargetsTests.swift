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

    private static let presetKeys = (CategoryPreset.defaultExpense + CategoryPreset.defaultIncome).map(\.nameKey)

    /// Each preset key's name in every app locale.
    private static func presetNamesByKey() -> [String: Set<String>] {
        var names: [String: Set<String>] = [:]
        for locale in locales {
            for bundle in [Bundle.main, Bundle(for: CategoriesViewModel.self)] {
                guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                      let table = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
                for key in presetKeys {
                    if let value = table[key] { names[key, default: []].insert(value) }
                }
                break
            }
        }
        return names
    }

    private static func presetNames() -> Set<String> {
        presetNamesByKey().values.reduce(into: Set<String>()) { $0.formUnion($1) }
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

    /// `VoiceInputParser.categoryGroups` resolves a keyword target to the user's
    /// category in another language, so each group must be exactly one preset's
    /// names across the locales, and no name may sit in two groups.
    @Test func categoryGroupsMatchThePresetNames() {
        let byKey = Self.presetNamesByKey()
        #expect(byKey.count == Self.presetKeys.count, "preset names were not loaded from the bundle")

        let expected = Set(byKey.values)
        let actual = Set(VoiceInputParser.categoryGroups.map(Set.init))
        #expect(actual == expected, "groups differ from the strings files: missing \(expected.subtracting(actual)), extra \(actual.subtracting(expected))")

        let all = VoiceInputParser.categoryGroups.flatMap { $0 }
        #expect(all.count == Set(all).count, "a name is listed twice")
    }
}
