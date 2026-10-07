//
//  TransactionAmountSearchTests.swift
//  TenraTests
//
//  History's numeric search used to format every transaction's amount with
//  `String(format:)` per debounced keystroke on the main actor. The index formats each
//  distinct amount once and answers with a binary search. Pinned against that scan,
//  copied below: the same ids for every query, odd amounts and odd queries included.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionAmountSearchTests {

    // MARK: - Reference: HistoryView's scan before 2026-10, verbatim

    private static func referenceMatch(query: String, transactions: [Transaction]) -> Set<String>? {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !needle.isEmpty,
              needle.contains(where: \.isNumber),
              needle.allSatisfy({ $0.isNumber || $0 == "." }),
              needle.filter({ $0 == "." }).count <= 1
        else { return nil }

        let matched = Set(
            transactions
                .lazy
                .filter { referencePrefixString($0.amount).hasPrefix(needle) }
                .map(\.id)
        )
        return matched.isEmpty ? nil : matched
    }

    private static func referencePrefixString(_ amount: Double) -> String {
        var s = String(format: "%.2f", abs(amount))
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// HistoryView's resolution with the index (nil when the query is not a number or
    /// nothing matches).
    private static func indexedMatch(query: String, index: TransactionAmountSearch.Index) -> Set<String>? {
        guard let needle = TransactionAmountSearch.needle(from: query) else { return nil }
        let matched = index.matchingIds(needle: needle)
        return matched.isEmpty ? nil : matched
    }

    // MARK: - Fixture

    private static func transaction(_ id: String, _ amount: Double) -> Transaction {
        Transaction(
            id: id, date: "2026-09-01", description: "", amount: amount,
            currency: "KZT", type: .expense, category: "Food"
        )
    }

    /// Round amounts, amounts with cents, repeated amounts, negatives, zero, values whose
    /// two-decimal rounding sits on a tie or a binary edge (14.995, 0.125, 2.675, 1.005),
    /// and very large ones.
    private static func fixture() -> [Transaction] {
        let special: [Double] = [
            0, -0.0, 15, 15.5, 150, 1500, 15_000, -42.5, 14.995, 0.125, 0.375, 0.625, 1.005,
            2.675, 99.999, 100.004, 0.1, 0.01, 1e7, 1e15, 123_456.78
        ]
        var seed: UInt64 = 11
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        var transactions = special.enumerated().map { transaction("s\($0.offset)", $0.element) }
        for i in 0..<4_000 {
            let amount: Double
            switch next(3) {
            case 0: amount = Double(next(200) * 500)                 // round, repeated
            case 1: amount = Double(next(10_000_000)) / 100          // cents
            default: amount = Double(next(1_000_000)) / 1_000        // three decimals
            }
            transactions.append(transaction("r\(i)", next(10) == 0 ? -amount : amount))
        }
        return transactions
    }

    private static let queries: [String] = {
        var queries = [
            "1", "15", "15.", "15.5", "15,5", " 15,5 ", "0", "0.", "0.1", "0.12", "0.13", "007",
            ".5", "1500", "1.0", "1.05", "1.00", "9", "99999999", "4", "14.99", "15.00", "100",
            "100.", "99.99", "0.38", "0.62", "0.63", "2.67", "2.68", "42", "42.5", "-42", "1e7",
            "10000000", "1000000000000000", "abc", "12a", "1.2.3", "", "  ", ".", "١٥", "１５",
            "½", "²"
        ]
        var seed: UInt64 = 3
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<300 {
            var query = (0...next(5)).map { _ in String(next(10)) }.joined()
            if next(3) == 0 {
                let position = query.index(query.startIndex, offsetBy: next(query.count + 1))
                query.insert(next(2) == 0 ? "." : ",", at: position)
            }
            queries.append(query)
        }
        return queries
    }()

    // MARK: - Tests

    @Test("the index returns the scan's ids for every query")
    func indexMatchesScan() {
        let transactions = Self.fixture()
        let index = TransactionAmountSearch.Index(transactions: transactions)
        var matchedQueries = 0

        for query in Self.queries {
            let reference = Self.referenceMatch(query: query, transactions: transactions)
            #expect(Self.indexedMatch(query: query, index: index) == reference, "query '\(query)'")
            if reference != nil { matchedQueries += 1 }
        }
        // Not vacuous: many queries match something (147 of the 346, the random ones
        // often have six digits or a separator no amount contains).
        #expect(matchedQueries > Self.queries.count / 3)
    }

    @Test("needle and canonical string are the scan's, unchanged")
    func needleAndPrefixStringUnchanged() {
        for query in Self.queries {
            let reference: String? = {
                let needle = query
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ".")
                guard !needle.isEmpty,
                      needle.contains(where: \.isNumber),
                      needle.allSatisfy({ $0.isNumber || $0 == "." }),
                      needle.filter({ $0 == "." }).count <= 1
                else { return nil }
                return needle
            }()
            #expect(TransactionAmountSearch.needle(from: query) == reference, "query '\(query)'")
        }
        for tx in Self.fixture() {
            #expect(TransactionAmountSearch.prefixString(tx.amount) == Self.referencePrefixString(tx.amount))
        }
        #expect(TransactionAmountSearch.prefixString(1500) == "1500")
        #expect(TransactionAmountSearch.prefixString(15.5) == "15.5")
        #expect(TransactionAmountSearch.prefixString(-42) == "42")
    }

    @Test("the cache rebuilds when the transaction set changes")
    func cacheFollowsTheTransactionSet() {
        let cache = TransactionAmountSearch.Cache()
        var transactions = [Self.transaction("a", 1_500), Self.transaction("b", 2_000)]
        let v1 = TransactionAmountSearch.Cache.Version(mutationVersion: 1, transactionCount: 2)

        // A background build in flight and the synchronous path give one answer.
        cache.prepare(transactions: transactions, version: v1)
        let first = cache.matchingIds(needle: "15", version: v1) { transactions }
        #expect(first == ["a"])

        transactions.append(Self.transaction("c", 15.5))
        let v2 = TransactionAmountSearch.Cache.Version(mutationVersion: 2, transactionCount: 3)
        let afterAdd = cache.matchingIds(needle: "15", version: v2) { transactions }
        #expect(afterAdd == ["a", "c"])

        // An edit keeps the count: the mutation version alone invalidates.
        transactions[0] = Self.transaction("a", 9_000)
        let v3 = TransactionAmountSearch.Cache.Version(mutationVersion: 3, transactionCount: 3)
        let afterEdit = cache.matchingIds(needle: "15", version: v3) { transactions }
        #expect(afterEdit == ["c"])
    }
}
