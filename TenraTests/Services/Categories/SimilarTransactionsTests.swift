//
//  SimilarTransactionsTests.swift
//  TenraTests
//
//  Pins which saved transactions the "apply to similar" prompt may touch after
//  the user changes one transaction's category: same merchant, same type, same
//  previous category, and never series-linked or subcategory-tagged rows.
//

import Testing
import Foundation
@testable import Tenra

struct SimilarTransactionsTests {

    private func tx(
        _ id: String,
        _ description: String,
        category: String = "",
        type: TransactionType = .expense,
        date: String = "2026-09-01",
        seriesId: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: 100,
            currency: "KZT",
            type: type,
            category: category,
            accountId: "a1",
            recurringSeriesId: seriesId
        )
    }

    private func similar(
        to edited: Transaction,
        previous: String = "",
        in all: [Transaction],
        links: [String: [String]] = [:]
    ) -> [String] {
        CategorySuggestionService.similarTransactionIds(
            to: edited,
            previousCategory: previous,
            in: all,
            subcategoryLinks: links
        )
    }

    @Test func sameMerchantVariantsAreIncluded() {
        let edited = tx("e", "MAGNUM 01", category: "Groceries")
        let all = [edited, tx("a", "Magnum-02", date: "2026-09-02"), tx("b", "MAGNUM", date: "2026-09-03")]
        #expect(similar(to: edited, in: all) == ["b", "a"])
    }

    @Test func differentMerchantIsExcluded() {
        let edited = tx("e", "MAGNUM", category: "Groceries")
        #expect(similar(to: edited, in: [edited, tx("a", "GALMART")]).isEmpty)
    }

    @Test func differentCurrentCategoryIsExcluded() {
        let edited = tx("e", "MAGNUM", category: "Groceries")
        #expect(similar(to: edited, in: [edited, tx("a", "MAGNUM", category: "Snacks")]).isEmpty)
    }

    @Test func differentTypeIsExcluded() {
        let edited = tx("e", "MAGNUM", category: "Groceries")
        #expect(similar(to: edited, in: [edited, tx("a", "MAGNUM", type: .income)]).isEmpty)
    }

    @Test func editedTransactionItselfIsExcluded() {
        let edited = tx("e", "MAGNUM", category: "Groceries")
        let previousVersion = tx("e", "MAGNUM")
        #expect(similar(to: edited, in: [previousVersion]).isEmpty)
    }

    @Test func seriesLinkedTransactionsAreExcluded() {
        let edited = tx("e", "NETFLIX", category: "Subscriptions")
        #expect(similar(to: edited, in: [edited, tx("a", "NETFLIX", seriesId: "s1")]).isEmpty)
    }

    @Test func subcategoryTaggedTransactionsAreExcluded() {
        let edited = tx("e", "MAGNUM", category: "Groceries")
        let all = [edited, tx("a", "MAGNUM"), tx("b", "MAGNUM")]
        #expect(similar(to: edited, in: all, links: ["a": ["sub1"], "b": []]) == ["b"])
    }

    @Test func transfersAndShortMerchantsProduceNothing() {
        let transfer = tx("e", "MAGNUM", category: TransactionType.transferCategoryName, type: .internalTransfer)
        #expect(similar(to: transfer, previous: TransactionType.transferCategoryName,
                        in: [transfer, tx("a", "MAGNUM", category: TransactionType.transferCategoryName, type: .internalTransfer)]).isEmpty)

        let digitsOnly = tx("e2", "12 34", category: "Groceries")
        #expect(similar(to: digitsOnly, in: [digitsOnly, tx("b", "12 34")]).isEmpty)
    }
}
