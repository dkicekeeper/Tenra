//
//  TransactionStore+SeriesIndex.swift
//  Tenra
//
//  Maintains:
//  • `transactionIdsBySeriesId` — O(1) lookup of all tx linked to a recurring series.
//  • `parsedDateByDateString`  — cached `FastDateParser.date(from: tx.date)`, keyed by
//    the date STRING so transactions sharing a day share one entry.
//
//  Wired into the same `updateState` funnel as `categoryIndexAdd` etc.
//

import Foundation

extension TransactionStore {

    // MARK: - Per-event Maintenance

    /// Add a transaction to the series-id index and cache its parsed date.
    internal func seriesIndexAdd(_ tx: Transaction) {
        // Idempotent: transactions sharing a date share the entry.
        if parsedDateByDateString[tx.date] == nil,
           let parsed = FastDateParser.date(from: tx.date) {
            parsedDateByDateString[tx.date] = parsed
        }
        guard let sid = tx.recurringSeriesId, !sid.isEmpty else { return }
        transactionIdsBySeriesId[sid, default: []].append(tx.id)
    }

    /// Remove a transaction from the series-id index.
    ///
    /// Deliberately does NOT touch `parsedDateByDateString`: the entry is keyed by date,
    /// so other transactions on the same day still need it. See the property's doc comment.
    internal func seriesIndexRemove(_ tx: Transaction) {
        guard let sid = tx.recurringSeriesId, !sid.isEmpty else { return }
        if var bucket = transactionIdsBySeriesId[sid],
           let i = bucket.firstIndex(of: tx.id) {
            bucket.remove(at: i)
            if bucket.isEmpty {
                transactionIdsBySeriesId.removeValue(forKey: sid)
            } else {
                transactionIdsBySeriesId[sid] = bucket
            }
        }
    }

    /// Apply a tx update — re-bucket if the series link or the date string changed.
    internal func seriesIndexUpdate(old: Transaction, new: Transaction) {
        // Date cache: only ever ADD the new date's entry. The old date's entry stays —
        // it is shared with every other transaction on that day, and evicting it here
        // would break their lookups. An unparseable new date simply gets no entry.
        if old.date != new.date,
           parsedDateByDateString[new.date] == nil,
           let parsed = FastDateParser.date(from: new.date) {
            parsedDateByDateString[new.date] = parsed
        }

        // Series-id bucket: same id → replace in place; different id → remove+add.
        let oldSid = old.recurringSeriesId ?? ""
        let newSid = new.recurringSeriesId ?? ""
        if oldSid == newSid {
            // Same bucket, same id — the bucket holds ids and resolves through
            // `transactionById`, which updateState refreshed before calling us.
            return
        }
        if !oldSid.isEmpty,
           var bucket = transactionIdsBySeriesId[oldSid],
           let i = bucket.firstIndex(of: old.id) {
            bucket.remove(at: i)
            if bucket.isEmpty {
                transactionIdsBySeriesId.removeValue(forKey: oldSid)
            } else {
                transactionIdsBySeriesId[oldSid] = bucket
            }
        }
        if !newSid.isEmpty {
            transactionIdsBySeriesId[newSid, default: []].append(new.id)
        }
    }

    // MARK: - Cold Rebuild

    /// Rebuild `transactionIdsBySeriesId` and `parsedDateByDateString` from the canonical
    /// `transactions` array. Called once during `loadData()`.
    internal func rebuildSeriesAndDateIndexes() {
        ensureTransactionByIdInSync()
        var byDate: [String: Date] = [:]
        var bySeries: [String: [String]] = [:]
        // ~1.8k distinct dates for a 19k set — not `transactions.count`.
        byDate.reserveCapacity(2048)
        bySeries.reserveCapacity(32)

        for tx in transactions {
            if byDate[tx.date] == nil, let parsed = FastDateParser.date(from: tx.date) {
                byDate[tx.date] = parsed
            }
            if let sid = tx.recurringSeriesId, !sid.isEmpty {
                bySeries[sid, default: []].append(tx.id)
            }
        }
        parsedDateByDateString = byDate
        transactionIdsBySeriesId = bySeries
    }
}
