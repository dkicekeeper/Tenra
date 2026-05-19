//
//  TransactionStore+SeriesIndex.swift
//  Tenra
//
//  Maintains:
//  • `transactionsBySeriesId`  — O(1) lookup of all tx linked to a recurring series.
//  • `parsedDateById`          — cached `DateFormatter.date(from: tx.date)` so the
//    parse cost (~16 µs/tx) is paid once per tx lifecycle, not per filter pass.
//
//  Wired into the same `updateState` funnel as `categoryIndexAdd` etc.
//

import Foundation

extension TransactionStore {

    // MARK: - Per-event Maintenance

    /// Add a transaction to the series-id index and cache its parsed date.
    internal func seriesIndexAdd(_ tx: Transaction) {
        if let parsed = DateFormatters.dateFormatter.date(from: tx.date) {
            parsedDateById[tx.id] = parsed
        }
        guard let sid = tx.recurringSeriesId, !sid.isEmpty else { return }
        transactionsBySeriesId[sid, default: []].append(tx)
    }

    /// Remove a transaction from the series-id index and date cache.
    internal func seriesIndexRemove(_ tx: Transaction) {
        parsedDateById.removeValue(forKey: tx.id)
        guard let sid = tx.recurringSeriesId, !sid.isEmpty else { return }
        if var bucket = transactionsBySeriesId[sid],
           let i = bucket.firstIndex(where: { $0.id == tx.id }) {
            bucket.remove(at: i)
            if bucket.isEmpty {
                transactionsBySeriesId.removeValue(forKey: sid)
            } else {
                transactionsBySeriesId[sid] = bucket
            }
        }
    }

    /// Apply a tx update — re-bucket if the series link or the date string changed.
    internal func seriesIndexUpdate(old: Transaction, new: Transaction) {
        // Date cache: re-parse only when the date string changed.
        if old.date != new.date {
            if let parsed = DateFormatters.dateFormatter.date(from: new.date) {
                parsedDateById[new.id] = parsed
            } else {
                parsedDateById.removeValue(forKey: new.id)
            }
        }

        // Series-id bucket: same id → replace in place; different id → remove+add.
        let oldSid = old.recurringSeriesId ?? ""
        let newSid = new.recurringSeriesId ?? ""
        if oldSid == newSid {
            guard !newSid.isEmpty else { return }
            if var bucket = transactionsBySeriesId[newSid],
               let i = bucket.firstIndex(where: { $0.id == new.id }) {
                bucket[i] = new
                transactionsBySeriesId[newSid] = bucket
            }
            return
        }
        if !oldSid.isEmpty,
           var bucket = transactionsBySeriesId[oldSid],
           let i = bucket.firstIndex(where: { $0.id == old.id }) {
            bucket.remove(at: i)
            if bucket.isEmpty {
                transactionsBySeriesId.removeValue(forKey: oldSid)
            } else {
                transactionsBySeriesId[oldSid] = bucket
            }
        }
        if !newSid.isEmpty {
            transactionsBySeriesId[newSid, default: []].append(new)
        }
    }

    // MARK: - Cold Rebuild

    /// Rebuild `transactionsBySeriesId` and `parsedDateById` from the canonical
    /// `transactions` array. Called once during `loadData()`.
    internal func rebuildSeriesAndDateIndexes() {
        var byId: [String: Date] = [:]
        var bySeries: [String: [Transaction]] = [:]
        byId.reserveCapacity(transactions.count)
        bySeries.reserveCapacity(32)

        let formatter = DateFormatters.dateFormatter
        for tx in transactions {
            if let parsed = formatter.date(from: tx.date) {
                byId[tx.id] = parsed
            }
            if let sid = tx.recurringSeriesId, !sid.isEmpty {
                bySeries[sid, default: []].append(tx)
            }
        }
        parsedDateById = byId
        transactionsBySeriesId = bySeries
    }
}
