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

    @Test("date and amount claiming the same column rejects the layout")
    func collidingDateAndAmountColumnsRejectsLayout() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: 0,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: 2,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    // MARK: - Fix 2 (CRITICAL): amount + debit/credit exclusivity

    @Test("amount and credit both resolved to distinct columns rejects the layout")
    func amountAndCreditBothResolvedRejectsLayout() {
        // The model's own @Guide text says amountColumn should be -1 "if the
        // table instead has separate money-out and money-in columns" — amount
        // and debit/credit are mutually exclusive by design. Before this fix,
        // only same-index collisions were rejected, so this layout (a real
        // Amount column plus a spuriously credit-tagged Balance column, at
        // different indices) passed validation. StatementInterpreter then
        // gives debit/credit absolute priority, so the running balance would
        // silently replace every row's real transaction amount.
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: 2,
            debitColumn: -1,
            creditColumn: 3,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    @Test("amount and debit both resolved to distinct columns rejects the layout")
    func amountAndDebitBothResolvedRejectsLayout() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: 2,
            debitColumn: 3,
            creditColumn: -1,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    @Test("debit and credit claiming the same column rejects the layout")
    func collidingDebitAndCreditColumnsRejectsLayout() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: -1,
            debitColumn: 2,
            creditColumn: 2,
            currencyColumn: -1,
            descriptionColumn: 1
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles == nil)
    }

    @Test("layout with every role resolved to a distinct column still resolves")
    func allDistinctIndicesResolve() {
        let layout = InferredColumnLayout(
            dateColumn: 0,
            amountColumn: 1,
            debitColumn: -1,
            creditColumn: -1,
            currencyColumn: 2,
            descriptionColumn: 3
        )
        let roles = IntelligentColumnRoleResolver.columnRoles(from: layout, columnCount: 4)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 1)
        #expect(roles?.currency == 2)
        #expect(roles?.description == 3)
    }

    // MARK: - Cancellation

    /// `resolve(table:)` checks `Task.checkCancellation()` before doing any
    /// Apple Intelligence work, so an already-cancelled task must throw
    /// `CancellationError` rather than returning nil (which would read as
    /// "model unavailable, fall back" instead of "the user backed out").
    /// This is the only slice of the cancellation behavior testable in the
    /// Simulator without Apple Intelligence: it does not exercise
    /// cancellation mid-`session.respond`.
    @Test("an already-cancelled task throws CancellationError instead of returning nil")
    func alreadyCancelledTaskThrows() async {
        let table = DocumentSnapshot.Table(rows: [["Date", "Amount"], ["2026-01-01", "10.00"]])
        let task = Task {
            try await IntelligentColumnRoleResolver.resolve(table: table)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
