//
//  TransactionAmountSearch.swift
//  Tenra
//
//  History's numeric search: typing "15" finds every transaction whose amount reads
//  15, 150, 1500, 15.50… (a prefix of the amount's canonical string, not "contains").
//
//  Why an index
//  ────────────
//  The match used to format every transaction's amount with `String(format:)`, ~19k
//  calls on the main actor per debounced keystroke. The canonical string depends only
//  on the amount, so `Index` formats each DISTINCT amount once, groups transaction ids
//  by string and sorts the strings. A query is then a binary search to the first string
//  that is >= the needle, plus a walk over the strings that start with it. `Cache`
//  builds the index off the main actor while the query is still being typed.
//
//  Contract: `Index.matchingIds(needle:)` returns exactly the ids the per-transaction
//  scan returned (`prefixString(tx.amount).hasPrefix(needle)` over every transaction).
//  Pinned by `TransactionAmountSearchTests` against that scan.
//

import Foundation

nonisolated enum TransactionAmountSearch {

    /// The digits a query searches amounts for, or nil when the query is not a number
    /// (text searches skip the amount match). Trims whitespace, accepts a comma as the
    /// decimal separator (RU keyboards) and at most one separator.
    nonisolated static func needle(from query: String) -> String? {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !needle.isEmpty,
              needle.contains(where: \.isNumber),
              needle.allSatisfy({ $0.isNumber || $0 == "." }),
              needle.filter({ $0 == "." }).count <= 1
        else { return nil }
        return needle
    }

    /// Canonical, grouping-free decimal string of an amount for prefix matching:
    /// 1500 → "1500", 15.5 → "15.5", -42 → "42". Rounded to currency precision (2 dp).
    nonisolated static func prefixString(_ amount: Double) -> String {
        var s = String(format: "%.2f", abs(amount))
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    // MARK: - Index

    /// Transaction ids grouped by canonical amount string, the strings sorted.
    nonisolated struct Index: Sendable {

        /// Unique canonical strings, ascending.
        private let keys: [String]
        /// `ids[i]`: every transaction whose amount reads `keys[i]`.
        private let ids: [[String]]

        nonisolated init(transactions: [Transaction]) {
            // A few thousand distinct amounts repeat across ~19k transactions: format each
            // once. (-0.0 and 0.0 share an entry; both read "0".)
            var keyByAmount: [Double: String] = [:]
            var idsByKey: [String: [String]] = [:]
            for tx in transactions {
                let key: String
                if let cached = keyByAmount[tx.amount] {
                    key = cached
                } else {
                    key = TransactionAmountSearch.prefixString(tx.amount)
                    keyByAmount[tx.amount] = key
                }
                idsByKey[key, default: []].append(tx.id)
            }
            let sortedKeys = idsByKey.keys.sorted()
            keys = sortedKeys
            ids = sortedKeys.map { idsByKey[$0] ?? [] }
        }

        /// Ids of the transactions whose canonical amount string starts with `needle`.
        ///
        /// The strings that start with the needle form one run in sorted order, beginning
        /// at the first string >= the needle: the keys are ASCII ("nan"/"inf" aside, digits
        /// and "."), which compares byte by byte. A needle no key can start with
        /// (non-ASCII digits) ends the walk at once; it matched nothing in the scan either.
        nonisolated func matchingIds(needle: String) -> Set<String> {
            var result = Set<String>()
            var i = lowerBound(of: needle)
            while i < keys.count, keys[i].hasPrefix(needle) {
                result.formUnion(ids[i])
                i += 1
            }
            return result
        }

        /// First index whose key is >= `needle`.
        private nonisolated func lowerBound(of needle: String) -> Int {
            var low = 0
            var high = keys.count
            while low < high {
                let mid = (low + high) / 2
                if keys[mid] < needle {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low
        }
    }

    // MARK: - Cache

    /// History's index for the current transaction set. `prepare` builds it off the main
    /// actor as soon as the typed text is a number (History applies the search 300 ms
    /// after the last keystroke); `matchingIds` builds it on the spot if that build has
    /// not landed yet, with the same result.
    @MainActor
    final class Cache {

        /// Identifies a transaction set: changes whenever transactions are added,
        /// edited or deleted.
        struct Version: Equatable, Sendable {
            let mutationVersion: Int
            let transactionCount: Int
        }

        private var index: Index?
        private var indexVersion: Version?
        private var pendingVersion: Version?

        init() {}

        /// Starts an off-main build for `version` unless one is built or under way.
        func prepare(transactions: [Transaction], version: Version) {
            guard indexVersion != version, pendingVersion != version else { return }
            pendingVersion = version
            Task { [weak self] in
                let built = await Task.detached(priority: .userInitiated) {
                    Index(transactions: transactions)
                }.value
                // A newer set (or a synchronous build) superseded this one: drop it.
                guard let self, self.pendingVersion == version else { return }
                self.index = built
                self.indexVersion = version
                self.pendingVersion = nil
            }
        }

        /// Ids of the transactions whose amount starts with `needle`, for the set
        /// identified by `version`.
        func matchingIds(
            needle: String,
            version: Version,
            transactions: () -> [Transaction]
        ) -> Set<String> {
            if indexVersion != version {
                index = Index(transactions: transactions())
                indexVersion = version
                pendingVersion = nil
            }
            return index?.matchingIds(needle: needle) ?? []
        }
    }
}
