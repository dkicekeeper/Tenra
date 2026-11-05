//
//  AmountSeparatorsTests.swift
//  TenraTests
//
//  Pins amounts in the reader's own number format (the owner's decision of 2026-11-05):
//  the decimal and grouping separators come from the phone's region, not a fixed "." and " ".
//

import Testing
import Foundation
@testable import Tenra

struct AmountSeparatorsTests {

    @Test("Kazakhstan in Russian: a comma and a no-break space")
    func russianKazakhstan() {
        let separators = DesignKitBridge.amountSeparators(for: Locale(identifier: "ru_KZ"))
        #expect(separators.decimal == ",")
        #expect(separators.grouping == "\u{00A0}")
    }

    @Test("The United States: a point and a comma")
    func unitedStates() {
        let separators = DesignKitBridge.amountSeparators(for: Locale(identifier: "en_US"))
        #expect(separators.decimal == ".")
        #expect(separators.grouping == ",")
    }

    @Test("Germany: a comma and a point")
    func germany() {
        let separators = DesignKitBridge.amountSeparators(for: Locale(identifier: "de_DE"))
        #expect(separators.decimal == ",")
        #expect(separators.grouping == ".")
    }
}
