//
//  TransactionIndexTests.swift
//  TenraTests
//
//  Covers the id-based grouping index introduced when the store stopped duplicating
//  `Transaction` values across `transactionsByAccount` / `ByCategoryName` / `BySeriesId`.
//
//  The riskiest part of that change was DELETING the in-place bucket rewrites in
//  `indexUpdate` / `categoryIndexUpdate` / `seriesIndexUpdate`. Those existed so an edited
//  transaction's new field values were visible through the index. Buckets now hold ids and
//  resolve through `transactionById`, so the edit should be visible for free — these tests
//  are what makes that a checked claim rather than an assumption.
//
//  Created 2026-07-28
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionIndexTests {

    private static func tx(
        id: String,
        date: String = "2026-05-19",
        amount: Double = 100,
        category: String = "Food",
        accountId: String? = "acct-1"
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "test",
            amount: amount,
            currency: "KZT",
            type: .expense,
            category: category,
            accountId: accountId
        )
    }

    // MARK: - Resolution semantics

    @Test("subscript resolves ids to values in bucket order")
    func resolvesInOrder() {
        let a = Self.tx(id: "a"), b = Self.tx(id: "b"), c = Self.tx(id: "c")
        let index = TransactionIndex(
            ids: ["k": ["c", "a", "b"]],
            byId: ["a": a, "b": b, "c": c]
        )
        #expect(index["k"]?.map(\.id) == ["c", "a", "b"])
    }

    @Test("absent key returns nil, matching Dictionary semantics")
    func absentKeyIsNil() {
        let index = TransactionIndex(ids: ["k": ["a"]], byId: ["a": Self.tx(id: "a")])
        // Call sites are written as `index[key] ?? []`, so nil (not []) is required.
        #expect(index["missing"] == nil)
        #expect(index["k"] != nil)
    }

    @Test("ids with no resolvable value are dropped, not crashed on")
    func unresolvableIdsAreDropped() {
        // A bucket can briefly reference a transaction that byId no longer holds
        // (mid-delete). It must read as absent rather than trapping.
        let index = TransactionIndex(
            ids: ["k": ["a", "ghost", "b"]],
            byId: ["a": Self.tx(id: "a"), "b": Self.tx(id: "b")]
        )
        #expect(index["k"]?.map(\.id) == ["a", "b"])
    }

    @Test("count(forKey:) reports bucket size without resolving")
    func bucketCountWithoutResolution() {
        let index = TransactionIndex(ids: ["k": ["a", "b", "c"]], byId: [:])
        // No entries resolve, but the bucket size is still known.
        #expect(index.count(forKey: "k") == 3)
        #expect(index["k"]?.isEmpty == true)
    }

    @Test("grouping initialiser round-trips a value-keyed dictionary")
    func groupingInitRoundTrips() {
        let a = Self.tx(id: "a"), b = Self.tx(id: "b")
        let index = TransactionIndex(grouping: ["x": [a, b], "y": [a]])
        #expect(index["x"]?.map(\.id) == ["a", "b"])
        #expect(index["y"]?.map(\.id) == ["a"])
        #expect(index.count == 2)
    }

    @Test("empty index is empty and resolves nothing")
    func emptyIndex() {
        #expect(TransactionIndex.empty.isEmpty)
        #expect(TransactionIndex.empty["anything"] == nil)
    }

    // MARK: - The claim that replaced the in-place bucket rewrites

    @Test("editing a transaction is visible through the index without touching buckets")
    func editIsVisibleWithoutBucketRewrite() {
        var byId = ["a": Self.tx(id: "a", amount: 100, category: "Food")]
        let ids = ["acct-1": ["a"]]

        // Same bucket, same id — only the value map is refreshed, exactly what
        // `updateState` does before calling the index-maintenance helpers.
        byId["a"] = Self.tx(id: "a", amount: 999, category: "Transport")

        let index = TransactionIndex(ids: ids, byId: byId)
        #expect(index["acct-1"]?.first?.amount == 999)
        #expect(index["acct-1"]?.first?.category == "Transport")
    }
}
