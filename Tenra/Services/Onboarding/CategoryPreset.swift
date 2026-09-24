//
//  CategoryPreset.swift
//  Tenra
//
//  Static catalog of preset expense categories offered during onboarding.
//

import Foundation

struct CategoryPreset: Identifiable, Hashable {
    let id: String
    let nameKey: String      // localization key, resolved at commit time
    let iconSource: IconSource
    let colorHex: String
    let type: TransactionType

    func makeSelectable(isSelected: Bool) -> SelectablePreset {
        SelectablePreset(preset: self, isSelected: isSelected)
    }
}

struct SelectablePreset: Identifiable, Hashable {
    var preset: CategoryPreset
    var isSelected: Bool

    var id: String { preset.id }
}

extension CategoryPreset {
    /// 15 expense-category presets. Names resolved via `String(localized:)` at commit time.
    /// Hex colours: first 12 from `CategoryColors` palette; last 3 are neutrals chosen
    /// outside the palette (brown / slate / light grey) — see spec §4.4.
    static let defaultExpense: [CategoryPreset] = [
        .init(id: "groceries",     nameKey: "onboarding.preset.groceries",     iconSource: .sfSymbol("cart.fill"),                     colorHex: "#22c55e", type: .expense),
        .init(id: "dining",        nameKey: "onboarding.preset.dining",        iconSource: .sfSymbol("fork.knife"),                    colorHex: "#f97316", type: .expense),
        .init(id: "transport",     nameKey: "onboarding.preset.transport",     iconSource: .sfSymbol("car.fill"),                      colorHex: "#3b82f6", type: .expense),
        .init(id: "housing",       nameKey: "onboarding.preset.housing",       iconSource: .sfSymbol("house.fill"),                    colorHex: "#a855f7", type: .expense),
        .init(id: "utilities",     nameKey: "onboarding.preset.utilities",     iconSource: .sfSymbol("bolt.fill"),                     colorHex: "#eab308", type: .expense),
        .init(id: "health",        nameKey: "onboarding.preset.health",        iconSource: .sfSymbol("pills.fill"),                    colorHex: "#f43f5e", type: .expense),
        .init(id: "clothing",      nameKey: "onboarding.preset.clothing",      iconSource: .sfSymbol("tshirt.fill"),                   colorHex: "#ec4899", type: .expense),
        .init(id: "entertainment", nameKey: "onboarding.preset.entertainment", iconSource: .sfSymbol("gamecontroller.fill"),           colorHex: "#8b5cf6", type: .expense),
        .init(id: "travel",        nameKey: "onboarding.preset.travel",        iconSource: .sfSymbol("airplane"),                      colorHex: "#06b6d4", type: .expense),
        .init(id: "education",     nameKey: "onboarding.preset.education",     iconSource: .sfSymbol("book.fill"),                     colorHex: "#6366f1", type: .expense),
        .init(id: "gifts",         nameKey: "onboarding.preset.gifts",         iconSource: .sfSymbol("gift.fill"),                     colorHex: "#10b981", type: .expense),
        .init(id: "subscriptions", nameKey: "onboarding.preset.subscriptions", iconSource: .sfSymbol("creditcard.fill"),               colorHex: "#14b8a6", type: .expense),
        .init(id: "pets",          nameKey: "onboarding.preset.pets",          iconSource: .sfSymbol("pawprint.fill"),                 colorHex: "#92400e", type: .expense),
        .init(id: "services",      nameKey: "onboarding.preset.services",      iconSource: .sfSymbol("wrench.and.screwdriver.fill"),   colorHex: "#64748b", type: .expense),
        .init(id: "other",         nameKey: "onboarding.preset.other",         iconSource: .sfSymbol("ellipsis.circle.fill"),          colorHex: "#9ca3af", type: .expense)
    ]

    /// Created automatically when onboarding finishes (not shown in the selection grid),
    /// so a new user's first income never dead-ends on "create a category first".
    /// The Russian name of `salary` must stay "Зарплата": voice keywords target it.
    static let defaultIncome: [CategoryPreset] = [
        .init(id: "salary",      nameKey: "onboarding.preset.salary",      iconSource: .sfSymbol("briefcase.fill"),   colorHex: "#16a34a", type: .income),
        .init(id: "otherIncome", nameKey: "onboarding.preset.otherIncome", iconSource: .sfSymbol("plus.circle.fill"), colorHex: "#64748b", type: .income)
    ]
}
