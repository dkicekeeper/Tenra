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

    @Test("The multiple of the usual expense, one decimal in the locale")
    func timesText() {
        let multiple = (84_900.0 / 6_100).formatted(.number.precision(.fractionLength(1)))
        #expect(LargeTransactionHeroCard.timesText(amount: 84_900, usual: 6_100).contains(multiple))
    }

    @Test("No usual expense reads as zero, not a division by zero")
    func noUsualExpense() {
        let zero = 0.0.formatted(.number.precision(.fractionLength(1)))
        #expect(LargeTransactionHeroCard.timesText(amount: 84_900, usual: 0).contains(zero))
    }
}
