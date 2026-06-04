//
//  VoiceInputParserAmountTests.swift
//  TenraTests
//
//  Pins amount extraction against the "year filter" regression: a bare number
//  in the 1900–2100 range (e.g. "2000 на такси") is an extremely common KZT
//  amount and MUST NOT be silently discarded as a year. The year heuristic is
//  only allowed to *de-prioritize* such a number when a real competing amount
//  exists in the same utterance.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct VoiceInputParserAmountTests {

    /// Builds a parser backed by empty in-memory ViewModels. Amount parsing
    /// doesn't depend on account/category data, so empty VMs are sufficient.
    /// VMs are returned and retained by the caller because the parser holds
    /// only weak references to them.
    private static func makeParser() -> (VoiceInputParser, CategoriesViewModel, AccountsViewModel, TransactionsViewModel) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let categoriesVM = CategoriesViewModel(repository: repo)
        let accountsVM = AccountsViewModel(repository: repo)
        let transactionsVM = TransactionsViewModel(repository: repo)
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesVM,
            accountsViewModel: accountsVM,
            transactionsViewModel: transactionsVM
        )
        return (parser, categoriesVM, accountsVM, transactionsVM)
    }

    @Test("lone year-shaped number is kept as the amount (2000 на такси)")
    func loneYearShapedNumberIsAmount() {
        let (parser, _categories, _accounts, _transactions) = Self.makeParser()
        _ = (_categories, _accounts, _transactions) // retain weakly-held VMs

        let result = parser.parse("2000 на такси")
        #expect(result.amount == Decimal(2000))
    }

    @Test("lone year-shaped number survives parseMulti too")
    func loneYearShapedNumberInParseMulti() {
        let (parser, _categories, _accounts, _transactions) = Self.makeParser()
        _ = (_categories, _accounts, _transactions)

        let ops = parser.parseMulti("2000 на такси")
        #expect(ops.count == 1)
        #expect(ops.first?.amount == Decimal(2000))
    }

    @Test("year is still de-prioritized when a real amount competes")
    func realAmountBeatsYear() {
        let (parser, _categories, _accounts, _transactions) = Self.makeParser()
        _ = (_categories, _accounts, _transactions)

        // "50 тысяч ... 2023 год" — the user means 50 000, not the year 2023.
        let result = parser.parse("Потратил 50 тысяч на машину за 2023 год")
        #expect(result.amount != nil)
        #expect(result.amount != Decimal(2023))
    }

    @Test("currency-tagged amount still beats a bare year-shaped number")
    func currencyAmountBeatsYear() {
        let (parser, _categories, _accounts, _transactions) = Self.makeParser()
        _ = (_categories, _accounts, _transactions)

        let result = parser.parse("2000 на такси 500 тенге")
        #expect(result.amount == Decimal(500))
    }
}
