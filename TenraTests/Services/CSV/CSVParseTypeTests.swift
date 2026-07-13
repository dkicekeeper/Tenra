//
//  CSVParseTypeTests.swift
//  TenraTests
//
//  H-8: the old bidirectional substring match ("in" ⊂ "internal transfer") could
//  misclassify transfer/deposit/loan rows as income on import — silent sign/balance
//  corruption. These pin the exact + length-guarded matching.
//

import Testing
import Foundation
@testable import Tenra

struct CSVParseTypeTests {

    private let mappings = CSVColumnMapping().typeMappings
    private let service = CSVValidationService(headers: [])

    @Test("canonical exported type names map exactly")
    func canonicalNamesExact() {
        #expect(service.parseType("expense", mappings: mappings) == .expense)
        #expect(service.parseType("income", mappings: mappings) == .income)
        #expect(service.parseType("internal", mappings: mappings) == .internalTransfer)
        #expect(service.parseType("deposit_interest", mappings: mappings) == .depositInterestAccrual)
        #expect(service.parseType("loan_payment", mappings: mappings) == .loanPayment)
    }

    @Test("short aliases still match exactly")
    func shortAliasesExact() {
        #expect(service.parseType("in", mappings: mappings) == .income)
        #expect(service.parseType("out", mappings: mappings) == .expense)
        #expect(service.parseType("+", mappings: mappings) == .income)
        #expect(service.parseType("-", mappings: mappings) == .expense)
    }

    @Test("'internal transfer' is NOT misclassified as income via the 'in' substring")
    func internalTransferNotIncome() {
        #expect(service.parseType("internal transfer", mappings: mappings) == .internalTransfer)
    }

    @Test("'deposit interest' (spaced) does not resolve to income")
    func depositInterestNotIncome() {
        #expect(service.parseType("deposit interest", mappings: mappings) != .income)
    }

    @Test("descriptive cells still fuzzy-match the canonical key")
    func descriptiveFuzzyMatch() {
        #expect(service.parseType("Expense transaction", mappings: mappings) == .expense)
    }

    @Test("German type values map correctly")
    func germanTypeValues() {
        #expect(service.parseType("Ausgabe", mappings: mappings) == .expense)
        #expect(service.parseType("Einnahme", mappings: mappings) == .income)
        #expect(service.parseType("Überweisung", mappings: mappings) == .internalTransfer)
        #expect(service.parseType("Umbuchung", mappings: mappings) == .internalTransfer)
    }
}
