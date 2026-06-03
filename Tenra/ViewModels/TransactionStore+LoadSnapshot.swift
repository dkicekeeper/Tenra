//
//  TransactionStore+LoadSnapshot.swift
//  Tenra
//
//  Cold-load index snapshot builder.
//
//  Owns the **pure, value-only** part of `loadData()` post-processing — every
//  hash-map, set, and per-tx grouping that can be derived from the loaded
//  arrays without touching MainActor state, FX rates, or settings.
//
//  Why: profiling showed loadData()'s "return to MainActor" path performed
//  5–7 sweeps over 19k transactions on the main queue (Dictionary build, Set
//  build, per-account/per-series/per-subcategory grouping, date parsing).
//  That work happened in parallel with the home screen's fade-in animation,
//  producing the visible "lag between loading and animation".
//
//  Now those sweeps run in a single `Task.detached` over Sendable inputs;
//  MainActor only performs hash-map assignments at the end.
//
//  Out of scope (still rebuilt on MainActor — Phase 2.2/2.3):
//  • `categoryAggregatesByKey` (depends on `baseCurrency`, FX cache, `LedgerPolicyRule`)
//  • `accountAggregatesByAccountId` (depends on `accountById` for currency lookup, FX)
//

import Foundation

extension TransactionStore {

    /// Sendable bundle of pre-built indexes produced off the main actor.
    /// Every field is a value type; the whole struct moves cheaply across actor hops.
    struct LoadedIndexSnapshot: Sendable {
        // Transaction-level
        let transactionIdSet: Set<String>
        let transactionById: [String: Transaction]
        let transactionsByAccount: [String: [Transaction]]
        let transactionsByCategoryName: [String: [Transaction]]
        let parsedDateById: [String: Date]
        let transactionsBySeriesId: [String: [Transaction]]
        // Category-level
        let categoryById: [String: CustomCategory]
        let categoryIdByName: [String: String]
        // Subcategory-level
        let subcategoryById: [String: Subcategory]
        let subcategoryIdsByCategoryId: [String: [String]]
        let subcategoryIdsByTransactionId: [String: [String]]
        let subcategoryUsageCountById: [String: Int]
        let subcategoryLastUsedById: [String: Date]
        // Cold-start aggregates — populated only when warm-start CoreData snapshots
        // were empty (first launch on a given schema version, or after a manual reset).
        // `nil` means caller should keep its current (warm-loaded) snapshot.
        let coldStartCategoryAggregates: [String: CategoryAggregate]?
        let coldStartCategoryAggregatesAreFXStale: Bool
        let coldStartAccountAggregates: [String: AccountAggregates]?
        let coldStartAccountAggregatesAreFXStale: Bool
    }

    /// Pure builder. Safe to call from any actor.
    ///
    /// Mirrors the on-MainActor logic of:
    /// • `rebuildAccountIndex(from:)`
    /// • `rebuildSeriesAndDateIndexes()`
    /// • `rebuildCategoryLookups()`
    /// • `rebuildAllSubcategoryIndexes()`
    /// • the `transactionsByCategoryName` half of `seedCategoryAggregates(from:)`
    /// • `rebuildCategoryIndexes()` and `rebuildAccountAggregates()` (when the
    ///   corresponding CoreData warm-start snapshot is empty)
    ///
    /// Aggregatability rule is duplicated locally to keep this helper free of
    /// MainActor-isolated instance methods — see `isAggregatableForLoad(_:)`.
    ///
    /// - Parameters:
    ///   - baseCurrency: current base currency used for category aggregate normalisation.
    ///   - accountsCurrencyById: account-id → currency map, used for account aggregate
    ///     leg conversion. Build on MainActor from `accounts` before detaching.
    ///   - needsColdStartCategoryAggregates: pass `true` when CoreData had no
    ///     `CategoryAggregateEntity` rows (first launch / fresh install).
    ///   - needsColdStartAccountAggregates: same for `AccountAggregateEntity`.
    nonisolated static func buildLoadSnapshot(
        transactions: [Transaction],
        categories: [CustomCategory],
        subcategories: [Subcategory],
        categorySubcategoryLinks: [CategorySubcategoryLink],
        transactionSubcategoryLinks: [TransactionSubcategoryLink],
        baseCurrency: String,
        accountsCurrencyById: [String: String],
        needsColdStartCategoryAggregates: Bool,
        needsColdStartAccountAggregates: Bool
    ) -> LoadedIndexSnapshot {

        let txCount = transactions.count

        // --- Transaction-level indexes (single pass) ---

        var idSet: Set<String> = []
        idSet.reserveCapacity(txCount)

        var byId: [String: Transaction] = [:]
        byId.reserveCapacity(txCount)

        var byAccount: [String: [Transaction]] = [:]
        byAccount.reserveCapacity(32)

        var byCategoryName: [String: [Transaction]] = [:]
        byCategoryName.reserveCapacity(64)

        var parsedDates: [String: Date] = [:]
        parsedDates.reserveCapacity(txCount)

        var bySeries: [String: [Transaction]] = [:]
        bySeries.reserveCapacity(32)

        let dateFormatter = DateFormatters.dateFormatter

        for tx in transactions {
            idSet.insert(tx.id)
            byId[tx.id] = tx

            if let aid = tx.accountId {
                byAccount[aid, default: []].append(tx)
            }
            if let tid = tx.targetAccountId {
                byAccount[tid, default: []].append(tx)
            }

            if isAggregatableForLoad(tx) {
                byCategoryName[tx.category, default: []].append(tx)
            }

            if let parsed = dateFormatter.date(from: tx.date) {
                parsedDates[tx.id] = parsed
            }

            if let sid = tx.recurringSeriesId, !sid.isEmpty {
                bySeries[sid, default: []].append(tx)
            }
        }

        // --- Category-level lookups ---

        var categoryById: [String: CustomCategory] = [:]
        var categoryIdByName: [String: String] = [:]
        categoryById.reserveCapacity(categories.count)
        categoryIdByName.reserveCapacity(categories.count)
        for cat in categories {
            categoryById[cat.id] = cat
            categoryIdByName[cat.name.lowercased()] = cat.id
        }

        // --- Subcategory-level indexes ---

        var subcategoryById: [String: Subcategory] = [:]
        subcategoryById.reserveCapacity(subcategories.count)
        for sub in subcategories {
            subcategoryById[sub.id] = sub
        }

        // subcategoryIdsByCategoryId — sorted by sortOrder ascending.
        var groupedByCategory: [String: [(Int, String)]] = [:]
        for link in categorySubcategoryLinks {
            groupedByCategory[link.categoryId, default: []].append((link.sortOrder, link.subcategoryId))
        }
        var subcategoryIdsByCategoryId: [String: [String]] = [:]
        subcategoryIdsByCategoryId.reserveCapacity(groupedByCategory.count)
        for (cat, pairs) in groupedByCategory {
            subcategoryIdsByCategoryId[cat] = pairs.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        // subcategoryIdsByTransactionId — order preserved as appended.
        var subcategoryIdsByTransactionId: [String: [String]] = [:]
        subcategoryIdsByTransactionId.reserveCapacity(transactionSubcategoryLinks.count / 2)
        for link in transactionSubcategoryLinks {
            subcategoryIdsByTransactionId[link.transactionId, default: []].append(link.subcategoryId)
        }

        // Subcategory usage stats — depend on the txid→subcatId map above, so build last.
        var subcategoryUsageCountById: [String: Int] = [:]
        var subcategoryLastUsedById: [String: Date] = [:]
        subcategoryUsageCountById.reserveCapacity(subcategories.count)
        subcategoryLastUsedById.reserveCapacity(subcategories.count)
        for tx in transactions {
            guard let ids = subcategoryIdsByTransactionId[tx.id], !ids.isEmpty else { continue }
            let txDate = parsedDates[tx.id] ?? Date()
            for id in ids {
                subcategoryUsageCountById[id, default: 0] += 1
                let prev = subcategoryLastUsedById[id] ?? .distantPast
                if txDate > prev { subcategoryLastUsedById[id] = txDate }
            }
        }

        // --- Cold-start aggregates (first launch only) ---
        // FX rate cache may be cold here. The MainActor path used to mark
        // `aggregatesAreFXStale = true` and let `bumpCurrencyRatesVersion` reconcile
        // once rates land. We preserve that semantics: `coldStartCategoryAggregatesAreFXStale`
        // is OR'd from each per-tx conversion that fell back to a stale rate.

        var coldStartCategoryAggregates: [String: CategoryAggregate]?
        var coldStartCategoryAggregatesAreFXStale = false
        if needsColdStartCategoryAggregates {
            var (cat, fxStale) = computeCategoryAggregates(
                transactions: transactions,
                parsedDates: parsedDates,
                baseCurrency: baseCurrency
            )
            coldStartCategoryAggregates = cat
            coldStartCategoryAggregatesAreFXStale = fxStale
            _ = cat
            _ = fxStale
        }

        var coldStartAccountAggregates: [String: AccountAggregates]?
        var coldStartAccountAggregatesAreFXStale = false
        if needsColdStartAccountAggregates {
            let (acc, fxStale) = computeAccountAggregates(
                transactions: transactions,
                parsedDates: parsedDates,
                accountsCurrencyById: accountsCurrencyById
            )
            coldStartAccountAggregates = acc
            coldStartAccountAggregatesAreFXStale = fxStale
        }

        return LoadedIndexSnapshot(
            transactionIdSet: idSet,
            transactionById: byId,
            transactionsByAccount: byAccount,
            transactionsByCategoryName: byCategoryName,
            parsedDateById: parsedDates,
            transactionsBySeriesId: bySeries,
            categoryById: categoryById,
            categoryIdByName: categoryIdByName,
            subcategoryById: subcategoryById,
            subcategoryIdsByCategoryId: subcategoryIdsByCategoryId,
            subcategoryIdsByTransactionId: subcategoryIdsByTransactionId,
            subcategoryUsageCountById: subcategoryUsageCountById,
            subcategoryLastUsedById: subcategoryLastUsedById,
            coldStartCategoryAggregates: coldStartCategoryAggregates,
            coldStartCategoryAggregatesAreFXStale: coldStartCategoryAggregatesAreFXStale,
            coldStartAccountAggregates: coldStartAccountAggregates,
            coldStartAccountAggregatesAreFXStale: coldStartAccountAggregatesAreFXStale
        )
    }

    // MARK: - Cold-start aggregates (pure, off-MainActor)

    /// Pure mirror of `rebuildCategoryIndexes()` + `applyAggregateDelta(...)`.
    /// Walks `transactions`, normalises each amount to `baseCurrency` via the
    /// shared `CategoryBudgetCurrency.toBase` helper, and patches the 4 granularity
    /// buckets per (category, year, month, day).
    ///
    /// Returns the resulting map and a flag indicating that at least one conversion
    /// used the stale-rate fallback — caller carries this through to
    /// `aggregatesAreFXStale` so `bumpCurrencyRatesVersion` reconciles on next FX update.
    private nonisolated static func computeCategoryAggregates(
        transactions: [Transaction],
        parsedDates: [String: Date],
        baseCurrency: String
    ) -> (aggregates: [String: CategoryAggregate], fxStale: Bool) {
        var aggregates: [String: CategoryAggregate] = [:]
        aggregates.reserveCapacity(512)
        var fxStale = false

        for tx in transactions where isAggregatableForLoad(tx) {
            guard let date = parsedDates[tx.id] else { continue }
            // Realized actuals only — exclude future-dated tx.
            guard LedgerPolicyRule.isRealized(date) else { continue }

            let conversion = CategoryBudgetCurrency.toBase(
                amount: tx.amount,
                from: tx.currency,
                base: baseCurrency
            )
            if conversion.usedStaleFallback { fxStale = true }
            let amount = conversion.amount
            let expense = tx.type == .expense ? amount : 0

            let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let y = Int16(comps.year ?? 0)
            let m = Int16(comps.month ?? 0)
            let d = Int16(comps.day ?? 0)

            patchColdBucket(into: &aggregates, category: tx.category,
                            y: y, m: m, d: d,
                            amount: amount, expense: expense, lastDate: date,
                            baseCurrency: baseCurrency)
            patchColdBucket(into: &aggregates, category: tx.category,
                            y: y, m: m, d: 0,
                            amount: amount, expense: expense, lastDate: date,
                            baseCurrency: baseCurrency)
            patchColdBucket(into: &aggregates, category: tx.category,
                            y: y, m: 0, d: 0,
                            amount: amount, expense: expense, lastDate: date,
                            baseCurrency: baseCurrency)
            patchColdBucket(into: &aggregates, category: tx.category,
                            y: 0, m: 0, d: 0,
                            amount: amount, expense: expense, lastDate: date,
                            baseCurrency: baseCurrency)
        }
        return (aggregates, fxStale)
    }

    /// Helper for `computeCategoryAggregates` — adds (amount, expense, count) to one bucket.
    /// Uses simple additive semantics because this is a cold rebuild (sign = +1 always);
    /// the production `patchBucket` supports remove/update, which we don't need here.
    private nonisolated static func patchColdBucket(
        into aggregates: inout [String: CategoryAggregate],
        category: String,
        y: Int16, m: Int16, d: Int16,
        amount: Double,
        expense: Double,
        lastDate: Date,
        baseCurrency: String
    ) {
        let key = CategoryAggregate.makeId(category: category, year: y, month: m, day: d)
        let existing = aggregates[key]
        let newTotal = (existing?.totalAmount ?? 0) + amount
        let newExpense = (existing?.expenseAmount ?? 0) + expense
        let newCount = Int32((existing?.transactionCount ?? 0)) + 1
        let newLast = max(existing?.lastTransactionDate ?? .distantPast, lastDate)
        aggregates[key] = CategoryAggregate(
            categoryName: category,
            subcategoryName: nil,
            year: y, month: m, day: d,
            totalAmount: newTotal,
            expenseAmount: newExpense,
            transactionCount: newCount,
            currency: baseCurrency,
            lastUpdated: Date(),
            lastTransactionDate: newLast
        )
    }

    /// Pure mirror of `rebuildAccountAggregates()` + `applyAccountAggregateDelta(...)`.
    /// Amounts stay in the OWNING account's currency (not base) — see ⚠️ #6 in CLAUDE.md.
    /// Cross-currency legs use `CurrencyConverter.convertSync` which is documented as
    /// safe from any actor.
    private nonisolated static func computeAccountAggregates(
        transactions: [Transaction],
        parsedDates: [String: Date],
        accountsCurrencyById: [String: String]
    ) -> (aggregates: [String: AccountAggregates], fxStale: Bool) {
        var aggregates: [String: AccountAggregates] = [:]
        aggregates.reserveCapacity(accountsCurrencyById.count)
        var fxStale = false

        for tx in transactions {
            // Realized actuals only — same gate as the production path.
            let date = parsedDates[tx.id]
            guard LedgerPolicyRule.isRealized(date) else { continue }

            // Source leg
            if let id = tx.accountId,
               let currency = accountsCurrencyById[id] {
                let amt = coldConvertSource(tx: tx, to: currency, fxStale: &fxStale)
                patchColdAccountBucket(into: &aggregates, accountId: id, tx: tx, signedAmount: amt, isSource: true)
            }
            // Target leg
            if let id = tx.targetAccountId, id != tx.accountId,
               let currency = accountsCurrencyById[id] {
                let amt = coldConvertTarget(tx: tx, to: currency, fxStale: &fxStale)
                patchColdAccountBucket(into: &aggregates, accountId: id, tx: tx, signedAmount: amt, isSource: false)
            }
        }
        return (aggregates, fxStale)
    }

    private nonisolated static func coldConvertSource(tx: Transaction, to: String, fxStale: inout Bool) -> Double {
        if tx.currency == to { return tx.amount }
        if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: to) {
            return fx
        }
        fxStale = true
        return tx.convertedAmount ?? tx.amount
    }

    private nonisolated static func coldConvertTarget(tx: Transaction, to: String, fxStale: inout Bool) -> Double {
        if tx.type == .internalTransfer,
           let targetAmount = tx.targetAmount,
           let targetCurrency = tx.targetCurrency {
            if targetCurrency == to { return targetAmount }
            if let fx = CurrencyConverter.convertSync(amount: targetAmount, from: targetCurrency, to: to) {
                return fx
            }
            fxStale = true
            return targetAmount
        }
        return coldConvertSource(tx: tx, to: to, fxStale: &fxStale)
    }

    private nonisolated static func patchColdAccountBucket(
        into aggregates: inout [String: AccountAggregates],
        accountId: String,
        tx: Transaction,
        signedAmount: Double,
        isSource: Bool
    ) {
        let existing = aggregates[accountId] ?? AccountAggregates(
            totalTransactions: 0, totalIncome: 0, totalExpense: 0
        )
        var income = existing.totalIncome
        var expense = existing.totalExpense
        let count = existing.totalTransactions + 1

        if isSource {
            switch tx.type {
            case .income:                    income  += signedAmount
            case .expense:                   expense += signedAmount
            case .internalTransfer:          expense += signedAmount
            case .depositTopUp:              expense += signedAmount
            case .depositWithdrawal:         expense += signedAmount
            case .depositInterestAccrual:    income  += signedAmount
            case .loanPayment,
                 .loanEarlyRepayment:        expense += signedAmount
            }
        } else {
            switch tx.type {
            case .income, .expense:                                            break
            case .internalTransfer:                       income  += signedAmount
            case .depositTopUp:                           income  += signedAmount
            case .depositWithdrawal:                      income  += signedAmount
            case .depositInterestAccrual:                 income  += signedAmount
            case .loanPayment, .loanEarlyRepayment:       expense += signedAmount
            }
        }

        aggregates[accountId] = AccountAggregates(
            totalTransactions: count,
            totalIncome: income,
            totalExpense: expense
        )
    }

    /// Copy of `isAggregatable(_:)` from TransactionStore+CategoryIndex.swift.
    /// Duplicated here so the snapshot builder stays `nonisolated static` —
    /// the production rule is a private instance method on MainActor.
    /// If the production rule changes, update this mirror too.
    private nonisolated static func isAggregatableForLoad(_ tx: Transaction) -> Bool {
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
