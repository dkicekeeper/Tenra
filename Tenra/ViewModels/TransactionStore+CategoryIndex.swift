//
//  TransactionStore+CategoryIndex.swift
//  Tenra
//
//  Incremental category-level indexes for O(1) reads.
//
//  Mirrors the `transactionsByAccount` pattern in TransactionStore: every
//  `apply(_:)` event funnels through `updateState(_:)`, which calls
//  `categoryIndexAdd/Remove/Update` to keep the in-memory hashmaps in sync.
//
//  Pre-aggregated `categoryAggregatesByKey` records are persisted lazily to
//  CoreData via `CategoryAggregateEntity` (debounced) so the next launch
//  starts hot without rebuilding from 19k transactions.
//
//  Currency conversion to `baseCurrency` happens here, at apply-time —
//  read-time consumers (CategoryBudgetService, CategoryAggregatesCalculator)
//  never touch FX rates. See CLAUDE.md ⚠️ #6.
//

import Foundation
import os.log

private let categoryIndexLogger = Logger(subsystem: "Tenra", category: "CategoryIndex")

extension TransactionStore {

    // MARK: - Per-event Maintenance

    /// Apply additive maintenance for one newly-added transaction.
    /// O(1) on `transactionIdsByCategoryName` insertion + O(4) bucket patches.
    internal func categoryIndexAdd(_ tx: Transaction) {
        guard isAggregatable(tx) else { return }
        transactionIdsByCategoryName[tx.category, default: []].append(tx.id)
        applyAggregateDelta(tx: tx, sign: 1)
    }

    /// Apply subtractive maintenance for one transaction being removed.
    internal func categoryIndexRemove(_ tx: Transaction) {
        guard isAggregatable(tx) else { return }
        if var bucket = transactionIdsByCategoryName[tx.category],
           let i = bucket.firstIndex(of: tx.id) {
            bucket.remove(at: i)
            if bucket.isEmpty {
                transactionIdsByCategoryName.removeValue(forKey: tx.category)
            } else {
                transactionIdsByCategoryName[tx.category] = bucket
            }
        }
        applyAggregateDelta(tx: tx, sign: -1)
    }

    /// Apply maintenance for a tx that changed fields. Falls back to remove+add
    /// when bucket-affecting fields (category, amount, currency, date, type) change;
    /// otherwise replaces the cached array element in place.
    internal func categoryIndexUpdate(old: Transaction, new: Transaction) {
        let oldEligible = isAggregatable(old)
        let newEligible = isAggregatable(new)

        let bucketAffecting = (old.category != new.category)
            || (old.amount != new.amount)
            || (old.currency != new.currency)
            || (old.date != new.date)
            || (old.type != new.type)

        if oldEligible && newEligible && !bucketAffecting {
            // Same bucket, same id, same totals. Buckets hold ids and resolve through
            // `transactionById` (already refreshed by updateState), so the edited field
            // values are visible without rewriting anything here.
            return
        }

        if oldEligible { categoryIndexRemove(old) }
        if newEligible { categoryIndexAdd(new) }
    }

    // MARK: - Bulk / Rebuild

    /// Rebuild all category indexes from scratch. Called during cold-start
    /// (`loadData()`) when CoreData has no `CategoryAggregateEntity` rows yet,
    /// from `reconcileCategoryAggregatesForFX()` when FX rates finally arrive,
    /// and from `updateBaseCurrency(_:)` (totals carry units, must be re-derived).
    ///
    /// `applyAggregateDelta` calls inside the loop each schedule a debounced
    /// persist; they coalesce to a single CoreData write thanks to the 500ms
    /// debounce — so the total cost is one save regardless of N_tx.
    internal func rebuildCategoryIndexes() {
        ensureTransactionByIdInSync()
        transactionIdsByCategoryName.removeAll(keepingCapacity: true)
        categoryAggregatesByKey.removeAll(keepingCapacity: true)
        aggregatesAreFXStale = false

        // Pre-size for typical workloads (≤30 categories, ≤19k tx).
        transactionIdsByCategoryName.reserveCapacity(64)
        categoryAggregatesByKey.reserveCapacity(categories.count * 8)

        for tx in transactions where isAggregatable(tx) {
            transactionIdsByCategoryName[tx.category, default: []].append(tx.id)
            applyAggregateDelta(tx: tx, sign: 1)
        }

        categoryIndexLogger.info(
            "rebuilt categoryAggregatesByKey: \(self.categoryAggregatesByKey.count, privacy: .public) buckets, fxStale=\(self.aggregatesAreFXStale, privacy: .public)"
        )
    }

    /// Seed `categoryAggregatesByKey` from a pre-loaded CoreData snapshot
    /// (warm-start path). Skips the O(N_tx) rebuild walk.
    /// Also rebuilds `transactionIdsByCategoryName` because that index isn't
    /// persisted in CoreData — but it's O(N_tx) without the FX conversion or
    /// per-bucket arithmetic, so it stays cheap.
    ///
    /// Use this when `transactionIdsByCategoryName` is NOT already populated.
    /// `loadData()` builds that map off-MainActor (see TransactionStore+LoadSnapshot.swift)
    /// and calls `seedCategoryAggregateBuckets(from:)` to skip the inner sweep.
    internal func seedCategoryAggregates(from snapshot: [CategoryAggregate]) {
        ensureTransactionByIdInSync()
        seedCategoryAggregateBuckets(from: snapshot)

        // Rebuild the in-memory transactions-by-category bucket index without
        // touching aggregate totals (those came from CoreData).
        transactionIdsByCategoryName.removeAll(keepingCapacity: true)
        transactionIdsByCategoryName.reserveCapacity(64)
        for tx in transactions where isAggregatable(tx) {
            transactionIdsByCategoryName[tx.category, default: []].append(tx.id)
        }
    }

    /// Seed only the `categoryAggregatesByKey` map — does NOT rebuild
    /// `transactionIdsByCategoryName`. Use when that bucket map is already
    /// populated (e.g. by `buildLoadSnapshot` during `loadData()`).
    internal func seedCategoryAggregateBuckets(from snapshot: [CategoryAggregate]) {
        var byKey: [String: CategoryAggregate] = [:]
        byKey.reserveCapacity(snapshot.count)
        for agg in snapshot { byKey[agg.id] = agg }
        categoryAggregatesByKey = byKey
        aggregatesAreFXStale = false
    }

    /// Debounced persistence of `categoryAggregatesByKey` to CoreData.
    /// Coalesces a burst of mutations (CSV import, recurring generation,
    /// rapid edits) into a single save instead of one per delta.
    /// Skipped during `isImporting` — caller flushes once via finishImport().
    internal func scheduleAggregatePersist() {
        guard !isImporting else { return }
        aggregatePersistDebounceTask?.cancel()
        aggregatePersistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            await self.flushAggregatePersist()
        }
    }

    /// Immediate persist of the current aggregate snapshot. Use after a
    /// wholesale rebuild (FX reconcile, baseCurrency change, finishImport).
    internal func flushAggregatePersist() async {
        let snapshot = Array(categoryAggregatesByKey.values)
        // Already routes through `saveCoordinator.performSave(...)` on a background context.
        repository.saveAggregates(snapshot)
    }

    /// Reseed `categoryById` and `categoryIdByName` from the canonical `categories` array.
    /// Call after bulk loads or explicit `syncCategories(...)`.
    internal func rebuildCategoryLookups() {
        var byId: [String: CustomCategory] = [:]
        var idByName: [String: String] = [:]
        byId.reserveCapacity(categories.count)
        idByName.reserveCapacity(categories.count)
        for cat in categories {
            byId[cat.id] = cat
            idByName[cat.name.lowercased()] = cat.id
        }
        categoryById = byId
        categoryIdByName = idByName
    }

    // MARK: - Rename Support

    /// When a category is renamed we must move keys in two maps so subsequent reads
    /// hit the right bucket. Aggregates are rebuilt locally for the affected category
    /// instead of a full sweep — this stays O(M) in the size of the category, not O(N_tx).
    internal func renameCategoryIndexKeys(from oldName: String, to newName: String) {
        guard oldName != newName else { return }

        // Move transactions-by-name bucket.
        if let bucket = transactionIdsByCategoryName.removeValue(forKey: oldName) {
            transactionIdsByCategoryName[newName] = bucket
        }

        // Re-key categoryIdByName.
        if let id = categoryIdByName.removeValue(forKey: oldName.lowercased()) {
            categoryIdByName[newName.lowercased()] = id
        }

        // Aggregates are keyed by *category name* (see CategoryAggregate.makeId).
        // Walk affected keys once and re-key them. We don't need to recompute totals
        // because the values are unchanged — only the key prefix moves.
        let prefix = "\(oldName)_"
        let movedKeys = categoryAggregatesByKey.keys.filter { $0.hasPrefix(prefix) }
        var anyMoved = false
        for oldKey in movedKeys {
            guard let agg = categoryAggregatesByKey.removeValue(forKey: oldKey) else { continue }
            let renamed = CategoryAggregate(
                categoryName: newName,
                subcategoryName: agg.subcategoryName,
                year: agg.year,
                month: agg.month,
                day: agg.day,
                totalAmount: agg.totalAmount,
                expenseAmount: agg.expenseAmount,
                transactionCount: agg.transactionCount,
                currency: agg.currency,
                lastUpdated: Date(),
                lastTransactionDate: agg.lastTransactionDate
            )
            categoryAggregatesByKey[renamed.id] = renamed
            anyMoved = true
        }
        if anyMoved { scheduleAggregatePersist() }
    }

    /// Drop every aggregate row belonging to a deleted category. Transactions
    /// keep the category name as a string (see CategoriesManagementView delete flow),
    /// so we do NOT clear `transactionIdsByCategoryName` — it stays correct.
    internal func dropAggregates(forCategoryName name: String) {
        let prefix = "\(name)_"
        let keys = categoryAggregatesByKey.keys.filter { $0.hasPrefix(prefix) }
        guard !keys.isEmpty else { return }
        for key in keys {
            categoryAggregatesByKey.removeValue(forKey: key)
        }
        scheduleAggregatePersist()
    }

    // MARK: - Aggregate Delta

    /// Patch the 4 granularity buckets for a single transaction.
    /// All amounts are normalised to `baseCurrency` before storage. If the rate
    /// cache is cold, we mark the index stale and reconcile on the next bump.
    /// Schedules a debounced persist so the cold-start fast path on the next
    /// launch can skip the O(N_tx) rebuild.
    private func applyAggregateDelta(tx: Transaction, sign: Int) {
        guard let date = DateFormatters.dateFormatter.date(from: tx.date) else { return }
        // Realized actuals only: exclude future-dated tx so budget "spent" and category
        // totals match the balance/account-aggregate policy. The day-change repair
        // (rebuildCategoryIndexes) folds a transaction in once its date arrives.
        guard LedgerPolicyRule.isRealized(date) else { return }

        let conversion = CategoryBudgetCurrency.toBase(amount: tx.amount, from: tx.currency, base: baseCurrency)
        if conversion.usedStaleFallback { aggregatesAreFXStale = true }
        let signedAmount = conversion.amount * Double(sign)
        // Expense-only contribution: budget "spent" reads `expenseAmount` so a
        // non-expense tx tagged to a budgeted expense category does not inflate it (C-6).
        let signedExpense = tx.type == .expense ? signedAmount : 0

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y = Int16(comps.year ?? 0)
        let m = Int16(comps.month ?? 0)
        let d = Int16(comps.day ?? 0)

        patchBucket(category: tx.category, y: y, m: m, d: d, signedAmount: signedAmount, signedExpense: signedExpense, sign: sign, lastDate: date)
        patchBucket(category: tx.category, y: y, m: m, d: 0, signedAmount: signedAmount, signedExpense: signedExpense, sign: sign, lastDate: date)
        patchBucket(category: tx.category, y: y, m: 0, d: 0, signedAmount: signedAmount, signedExpense: signedExpense, sign: sign, lastDate: date)
        patchBucket(category: tx.category, y: 0, m: 0, d: 0, signedAmount: signedAmount, signedExpense: signedExpense, sign: sign, lastDate: date)

        scheduleAggregatePersist()
    }

    private func patchBucket(
        category: String,
        y: Int16, m: Int16, d: Int16,
        signedAmount: Double,
        signedExpense: Double,
        sign: Int,
        lastDate: Date
    ) {
        let key = CategoryAggregate.makeId(category: category, year: y, month: m, day: d)
        let existing = categoryAggregatesByKey[key]
        let newTotal = (existing?.totalAmount ?? 0) + signedAmount
        let newExpense = (existing?.expenseAmount ?? 0) + signedExpense
        let newCount = Int32((existing?.transactionCount ?? 0)) + Int32(sign)

        // Drop empty buckets to keep the map compact. Use a tiny epsilon to absorb
        // floating-point residue from FX-amount add/subtract pairs.
        if newCount <= 0 && abs(newTotal) < 0.005 {
            categoryAggregatesByKey.removeValue(forKey: key)
            return
        }

        let resolvedLast: Date
        if sign > 0 {
            resolvedLast = max(existing?.lastTransactionDate ?? .distantPast, lastDate)
        } else {
            // On remove we keep the previous lastTransactionDate — recomputing it accurately
            // would require scanning the bucket; staleness here is bounded and self-heals on
            // the next add to the same bucket.
            resolvedLast = existing?.lastTransactionDate
                ?? (existing?.transactionCount ?? 0 > 0 ? lastDate : .distantPast)
        }

        categoryAggregatesByKey[key] = CategoryAggregate(
            categoryName: category,
            subcategoryName: nil,
            year: y, month: m, day: d,
            totalAmount: newTotal,
            expenseAmount: newExpense,
            transactionCount: max(newCount, 0),
            currency: baseCurrency,
            lastUpdated: Date(),
            lastTransactionDate: resolvedLast
        )
    }

    // MARK: - Eligibility

    /// Aggregates only carry expense + income flows where a category exists.
    /// Internal transfers and zero-amount adjustments do not contribute.
    private func isAggregatable(_ tx: Transaction) -> Bool {
        guard !tx.category.isEmpty else { return false }
        switch tx.type {
        case .expense, .income,
             .depositTopUp, .depositWithdrawal, .depositInterestAccrual,
             .loanPayment, .loanEarlyRepayment:
            return true
        case .internalTransfer:
            return false
        }
    }
}
