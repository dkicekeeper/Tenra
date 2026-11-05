//
//  SaveHintTests.swift
//  TenraTests
//
//  Pins when the add form's one-time hint on the save buttons shows (backlog "First run": a
//  newcomer read "Вчера / Сегодня / Дата" as a date picker and left unsaved). Only for a
//  newcomer, once, and only after an amount is typed.
//

import Testing
import Foundation
@testable import Tenra

struct SaveHintTests {

    @Test("A newcomer's first amount shows it")
    func newcomerWithAnAmount() {
        #expect(FeatureTourState.shouldShowSaveHint(amount: 3500, hasTransactions: false, seen: false))
    }

    @Test("No amount yet, no hint")
    func noAmount() {
        #expect(!FeatureTourState.shouldShowSaveHint(amount: nil, hasTransactions: false, seen: false))
        #expect(!FeatureTourState.shouldShowSaveHint(amount: 0, hasTransactions: false, seen: false))
    }

    @Test("Someone with a history knows the buttons")
    func someoneWithAHistory() {
        #expect(!FeatureTourState.shouldShowSaveHint(amount: 3500, hasTransactions: true, seen: false))
    }

    @Test("Shown once")
    func onlyOnce() {
        #expect(!FeatureTourState.shouldShowSaveHint(amount: 3500, hasTransactions: false, seen: true))
    }
}
