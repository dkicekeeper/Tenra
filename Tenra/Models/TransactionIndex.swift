//
//  TransactionIndex.swift
//  Tenra
//
//  A grouping index that stores transaction IDs and resolves them on read.
//
//  Why not `[String: [Transaction]]`
//  ─────────────────────────────────
//  `Transaction` has a 256-byte stride (measured). `TransactionStore` used to keep three
//  grouping dictionaries holding full `Transaction` values — by account (two legs per
//  transfer), by category name, and by series — on top of `transactions` and
//  `transactionById`. For a 19k set that is roughly 4.3 copies of the same data,
//  ~20 MB of index for a 4.75 MB payload.
//
//  `transactionById` is already the authoritative id → value map, so the grouping layer
//  only needs ids. This type stores `[String: [String]]` and resolves through that map on
//  subscript, so callers keep writing `index[accountId] ?? []` and still get
//  `[Transaction]`.
//
//  Cost trade
//  ──────────
//  Reading a bucket is now O(bucket) dictionary lookups instead of a single array retain.
//  For the real access pattern — one bucket per account/category, immediately filtered or
//  summed — that is a few microseconds against roughly 10 MB saved. Do NOT call the
//  subscript repeatedly for the same key inside a loop; bind it to a `let` first.
//
//  Both stored dictionaries are COW value types, so constructing a `TransactionIndex`
//  from the store retains buffers rather than copying them.
//

import Foundation

struct TransactionIndex: Sendable {

    /// Bucket key → transaction ids, in insertion order.
    private let ids: [String: [String]]

    /// Authoritative id → value map (`TransactionStore.transactionById`).
    private let byId: [String: Transaction]

    /// Wraps a store-maintained id index. Both arguments are retained, not copied.
    nonisolated init(ids: [String: [String]], byId: [String: Transaction]) {
        self.ids = ids
        self.byId = byId
    }

    /// Materialising initialiser for callers that have no store-maintained index —
    /// previews, tests, and the local-fallback path in `AccountRankingService`.
    nonisolated init(grouping buckets: [String: [Transaction]]) {
        var ids: [String: [String]] = [:]
        var byId: [String: Transaction] = [:]
        ids.reserveCapacity(buckets.count)
        for (key, txs) in buckets {
            ids[key] = txs.map(\.id)
            for tx in txs { byId[tx.id] = tx }
        }
        self.ids = ids
        self.byId = byId
    }

    /// Empty index — used as the "no data" default.
    nonisolated static var empty: TransactionIndex { TransactionIndex(ids: [:], byId: [:]) }

    /// Resolves a bucket to values. Returns `nil` when the key is absent, matching
    /// `Dictionary` semantics so existing `index[key] ?? []` call sites are unchanged.
    ///
    /// Ids with no entry in `byId` are dropped rather than crashing: a bucket can briefly
    /// outlive its transaction during a mutation, and a missing row should read as absent.
    nonisolated subscript(key: String) -> [Transaction]? {
        guard let bucket = ids[key] else { return nil }
        return bucket.compactMap { byId[$0] }
    }

    /// True when no buckets exist. O(1) — does not resolve anything.
    nonisolated var isEmpty: Bool { ids.isEmpty }

    /// Number of buckets (not transactions). O(1).
    nonisolated var count: Int { ids.count }

    /// Bucket keys. O(1) — does not resolve anything.
    nonisolated var keys: Dictionary<String, [String]>.Keys { ids.keys }

    /// Bucket size without materialising the values. O(1).
    nonisolated func count(forKey key: String) -> Int { ids[key]?.count ?? 0 }
}
