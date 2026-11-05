//
//  FeatureTourState.swift
//  Tenra
//
//  UserDefaults-backed "already shown" flags for the one-time feature hints (DesignKit's
//  `.spotlight`): each hint shows once, the first time its feature is on screen.
//

import Foundation

enum FeatureTourState {
    enum Hint: String, Hashable {
        /// The voice orb is the stop button (voice input).
        case voiceStopOrb = "featureTour.voiceStopOrb"
        /// A tap on a category on Home adds an expense (the first launch, the grid in a spotlight).
        case homeCategories = "featureTour.homeCategories"
        /// "Вчера / Сегодня / Дата" in the add form save the expense (a newcomer read them as a
        /// date picker and left unsaved).
        case addFormSave = "featureTour.addFormSave"
    }

    /// The add form's save hint: once, for a newcomer (no transactions yet), after an amount is
    /// typed. Someone with a history found the buttons long ago.
    static func shouldShowSaveHint(amount: Decimal?, hasTransactions: Bool, seen: Bool) -> Bool {
        guard !seen, !hasTransactions, let amount else { return false }
        return amount > 0
    }

    static func hasSeen(_ hint: Hint) -> Bool {
        UserDefaults.standard.bool(forKey: hint.rawValue)
    }

    static func markSeen(_ hint: Hint) {
        UserDefaults.standard.set(true, forKey: hint.rawValue)
    }
}
