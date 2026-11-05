//
//  AmountHeroCardsTests.swift
//  TenraTests
//
//  The large expense's hero says how many times the usual expense it is, with one decimal in
//  the app's locale, and stays readable without a usual expense to compare with.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct AmountHeroCardsTests {

    @Test("The multiple of the usual expense, one decimal in the chosen format")
    func timesText() {
        let multiple = NumberDisplay.decimal(84_900.0 / 6_100, fractionDigits: 1)
        #expect(LargeTransactionHeroCard.timesText(amount: 84_900, usual: 6_100).contains(multiple))
    }

    @Test("No usual expense reads as zero, not a division by zero")
    func noUsualExpense() {
        let zero = NumberDisplay.decimal(0, fractionDigits: 1)
        #expect(LargeTransactionHeroCard.timesText(amount: 84_900, usual: 0).contains(zero))
    }
}
