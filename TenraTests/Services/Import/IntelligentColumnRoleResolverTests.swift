//
//  IntelligentColumnRoleResolverTests.swift
//  TenraTests
//
//  Pins the pure index-validation logic that turns a model-inferred layout
//  into ColumnRoles. SystemLanguageModel availability and model responses
//  depend on the device and on whether Apple Intelligence assets are
//  downloaded, so only this deterministic piece is unit-testable.
//

import Testing
@testable import Tenra

struct IntelligentColumnRoleResolverTests {

    @Test("valid layout with a single amount column maps to ColumnRoles")
    func validSingleAmountLayout() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: 2,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: 3,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 2)
        #expect(roles?.debit == nil)
        #expect(roles?.credit == nil)
        #expect(roles?.currency == 3)
        #expect(roles?.description == 1)
        #expect(roles?.confidence == 0.8)
    }

    @Test("valid layout with debit/credit pair maps to ColumnRoles")
    func validDebitCreditLayout() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: -1,
            debitColumn: 2,
            creditColumn: 3,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles?.date == 0)
        #expect(roles?.amount == nil)
        #expect(roles?.debit == 2)
        #expect(roles?.credit == 3)
        #expect(roles?.currency == nil)
    }

    @Test("out-of-range date column rejects the layout")
    func outOfRangeDateColumn() {
        let layout = InferredColumnLayout(
            dateColumn: 5,
            amountColumn: 2,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    @Test("negative sentinel date column rejects the layout")
    func sentinelDateColumn() {
        let layout = InferredColumnLayout(
            dateColumn: -1,
            amountColumn: 2,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    @Test("no amount, debit, or credit signal rejects the layout")
    func noAmountSignal() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: -1,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    @Test("out-of-range secondary indices are dropped, not rejected")
    func outOfRangeSecondaryIndicesAreDropped() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: 2,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: 9,
            descriptionColumn: 9
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 2)
        #expect(roles?.currency == nil)
        #expect(roles?.description == nil)
    }
}
