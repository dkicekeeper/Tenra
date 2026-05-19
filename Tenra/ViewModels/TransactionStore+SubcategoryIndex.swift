//
//  TransactionStore+SubcategoryIndex.swift
//  Tenra
//
//  Incremental subcategory indexes for O(1) reads.
//
//  Tracks three families of state:
//  • `subcategoryById` — single source of truth for subcategory metadata by id.
//  • `subcategoryIdsByCategoryId` / `subcategoryIdsByTransactionId` — pre-sorted
//     id lists so consumers can skip the per-call filter/sort over the link tables.
//  • `subcategoryUsageCountById` / `subcategoryLastUsedById` — running counters,
//     maintained as transactions arrive instead of recomputed at read time
//     (the old read path scanned 19k tx + N_links per call).
//
//  Maintenance is wired into:
//    • TransactionStore.updateState (`.added` / `.updated` / `.deleted` / `.bulkAdded`)
//    • Subcategory CRUD funnels (addSubcategory / updateSubcategories /
//       updateCategorySubcategoryLinks / updateTransactionSubcategoryLinks)
//

import Foundation

extension TransactionStore {

    // MARK: - Per-transaction Maintenance

    /// Increment usage counters when a tx is added. Subcategory link rows are
    /// loaded asynchronously, so the helper looks at `subcategoryIdsByTransactionId`
    /// — which is populated either by `updateTransactionSubcategoryLinks` or by an
    /// explicit link write that happens after createSeries (see CLAUDE.md ⚠️ #5).
    internal func subcategoryIndexAdd(_ tx: Transaction) {
        guard let ids = subcategoryIdsByTransactionId[tx.id], !ids.isEmpty else { return }
        let txDate = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
        for id in ids {
            subcategoryUsageCountById[id, default: 0] += 1
            let prev = subcategoryLastUsedById[id] ?? .distantPast
            if txDate > prev { subcategoryLastUsedById[id] = txDate }
        }
    }

    /// Decrement counters when a tx is removed. Last-used date is intentionally NOT
    /// re-derived (would need a scan of the bucket); it self-corrects on the next
    /// add to the same subcategory.
    internal func subcategoryIndexRemove(_ tx: Transaction) {
        guard let ids = subcategoryIdsByTransactionId[tx.id], !ids.isEmpty else { return }
        for id in ids {
            if let count = subcategoryUsageCountById[id] {
                let next = count - 1
                if next <= 0 {
                    subcategoryUsageCountById.removeValue(forKey: id)
                } else {
                    subcategoryUsageCountById[id] = next
                }
            }
        }
    }

    /// Apply a tx update — usage counters move with the link membership, last-used
    /// date moves with the date. Bucket-affecting changes funnel through remove+add.
    internal func subcategoryIndexUpdate(old: Transaction, new: Transaction) {
        if old.date == new.date { return }  // counters unchanged, last-used updated lazily
        subcategoryIndexRemove(old)
        subcategoryIndexAdd(new)
    }

    // MARK: - Link Table Maintenance

    /// Rebuild `subcategoryIdsByCategoryId` from the current `categorySubcategoryLinks`.
    /// Order is determined by `CategorySubcategoryLink.sortOrder` ascending.
    internal func rebuildSubcategoryIdsByCategoryId() {
        var grouped: [String: [(Int, String)]] = [:]
        for link in categorySubcategoryLinks {
            grouped[link.categoryId, default: []].append((link.sortOrder, link.subcategoryId))
        }
        var result: [String: [String]] = [:]
        result.reserveCapacity(grouped.count)
        for (cat, pairs) in grouped {
            result[cat] = pairs.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        subcategoryIdsByCategoryId = result
    }

    /// Rebuild `subcategoryIdsByTransactionId` from the current `transactionSubcategoryLinks`.
    internal func rebuildSubcategoryIdsByTransactionId() {
        var result: [String: [String]] = [:]
        result.reserveCapacity(transactionSubcategoryLinks.count / 2)
        for link in transactionSubcategoryLinks {
            result[link.transactionId, default: []].append(link.subcategoryId)
        }
        subcategoryIdsByTransactionId = result
    }

    /// Rebuild `subcategoryById` from the canonical `subcategories` array.
    internal func rebuildSubcategoryById() {
        var byId: [String: Subcategory] = [:]
        byId.reserveCapacity(subcategories.count)
        for sub in subcategories {
            byId[sub.id] = sub
        }
        subcategoryById = byId
    }

    /// Recompute `subcategoryUsageCountById` and `subcategoryLastUsedById` from
    /// the current `transactions` array and `subcategoryIdsByTransactionId` map.
    /// One O(N_tx) pass — only called on cold-start, never on hot path.
    internal func rebuildSubcategoryUsageStats() {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        counts.reserveCapacity(subcategories.count)
        lastUsed.reserveCapacity(subcategories.count)

        for tx in transactions {
            guard let ids = subcategoryIdsByTransactionId[tx.id], !ids.isEmpty else { continue }
            let txDate = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
            for id in ids {
                counts[id, default: 0] += 1
                let prev = lastUsed[id] ?? .distantPast
                if txDate > prev { lastUsed[id] = txDate }
            }
        }

        subcategoryUsageCountById = counts
        subcategoryLastUsedById = lastUsed
    }

    /// One-shot rebuild of all subcategory indexes. Cheap (O(N_links + N_tx))
    /// and only used on cold-start or after bulk imports.
    internal func rebuildAllSubcategoryIndexes() {
        rebuildSubcategoryById()
        rebuildSubcategoryIdsByCategoryId()
        rebuildSubcategoryIdsByTransactionId()
        rebuildSubcategoryUsageStats()
    }
}
