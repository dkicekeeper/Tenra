//
//  ParsedTransactionMapperTests.swift
//  TenraTests
//
//  Pins ParsedTransaction -> Transaction mapping: amounts stay positive with
//  direction carried in TransactionType (never negated), currency falls back
//  to the caller's default, and every produced transaction gets a unique id.
//

import Testing
@testable import Tenra

struct ParsedTransactionMapperTests {

    @Test("expense direction maps to the expense TransactionType, amount stays positive")
    func expenseMapsToExpenseType() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 2500,
            currency: "KZT",
            descriptionText: "Supermarket",
            direction: .expense
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result.count == 1)
        #expect(result[0].type == .expense)
        #expect(result[0].amount == 2500)
    }

    @Test("income direction maps to the income TransactionType, amount stays positive")
    func incomeMapsToIncomeType() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 450_000,
            currency: "KZT",
            descriptionText: "Salary",
            direction: .income
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result.count == 1)
        #expect(result[0].type == .income)
        #expect(result[0].amount == 450_000)
    }

    @Test("transfer direction maps to internalTransfer with the canonical transfer category")
    func transferMapsToInternalTransferType() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 50_000,
            currency: "KZT",
            descriptionText: "Between own accounts",
            direction: .transfer
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result.count == 1)
        #expect(result[0].type == .internalTransfer)
        #expect(result[0].category == TransactionType.transferCategoryName)
    }

    @Test("nil currency falls back to the caller's default currency")
    func nilCurrencyFallsBackToDefault() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 1000,
            currency: nil,
            descriptionText: "No currency marker",
            direction: .expense
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "USD")

        #expect(result[0].currency == "USD")
    }

    @Test("an explicit currency is preserved over the default")
    func explicitCurrencyIsPreserved() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 1000,
            currency: "EUR",
            descriptionText: "Has currency marker",
            direction: .expense
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "USD")

        #expect(result[0].currency == "EUR")
    }

    @Test("descriptionText lands in Transaction.description and date is preserved verbatim")
    func descriptionAndDatePreserved() {
        let parsed = ParsedTransaction(
            date: "2026-01-05",
            amount: 999,
            currency: "KZT",
            descriptionText: "Coffee shop",
            direction: .expense
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result[0].description == "Coffee shop")
        #expect(result[0].date == "2026-01-05")
    }

    @Test("accountId is left nil for the preview screen to assign per row")
    func accountIdIsNil() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 100,
            currency: "KZT",
            descriptionText: "Something",
            direction: .expense
        )
        let statement = ParsedStatement(transactions: [parsed], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result[0].accountId == nil)
    }

    @Test("each produced transaction gets a unique id")
    func eachTransactionGetsUniqueId() {
        let parsed = ParsedTransaction(
            date: "2026-08-10",
            amount: 100,
            currency: "KZT",
            descriptionText: "Duplicate-looking row",
            direction: .expense
        )
        let statement = ParsedStatement(
            transactions: [parsed, parsed, parsed],
            skipped: [],
            resolvedRoles: nil
        )

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result.count == 3)
        #expect(Set(result.map(\.id)).count == 3)
    }

    @Test("mapping preserves statement order")
    func mappingPreservesOrder() {
        let first = ParsedTransaction(date: "2026-08-01", amount: 1, currency: "KZT", descriptionText: "First", direction: .expense)
        let second = ParsedTransaction(date: "2026-08-02", amount: 2, currency: "KZT", descriptionText: "Second", direction: .income)
        let statement = ParsedStatement(transactions: [first, second], skipped: [], resolvedRoles: nil)

        let result = ParsedTransactionMapper.transactions(from: statement, defaultCurrency: "KZT")

        #expect(result.map(\.description) == ["First", "Second"])
    }
}
