//
//  HistoryCategoryPredicateTests.swift
//  TenraTests
//
//  History used to apply only ONE category of a multi-selection (an arbitrary
//  element of a Set) and matched the "Uncategorized" label literally, so rows
//  stored with an empty category could never be found. Pins the predicate.
//

import Testing
import Foundation
@testable import Tenra

struct HistoryCategoryPredicateTests {

    private let label = "Uncategorized"

    private func matches(_ names: Set<String>, _ category: String) -> Bool {
        TransactionPaginationController
            .categoryPredicate(for: names, uncategorizedLabel: label)
            .evaluate(with: ["category": category])
    }

    @Test func everySelectedCategoryMatches() {
        #expect(matches(["Food", "Taxi"], "Food"))
        #expect(matches(["Food", "Taxi"], "Taxi"))
        #expect(!matches(["Food", "Taxi"], "Gifts"))
    }

    @Test func uncategorizedLabelMatchesEmptyCategory() {
        #expect(matches([label], ""))
        #expect(!matches([label], "Food"))
    }

    @Test func mixedSelectionMatchesBoth() {
        #expect(matches(["Food", label], "Food"))
        #expect(matches(["Food", label], ""))
        #expect(!matches(["Food", label], "Taxi"))
    }
}
