//
//  TransactionStore+AccountAggregates.swift
//  Tenra
//
//  Maintains `accountAggregatesByAccountId` — pre-computed (count, totalIncome,
//  totalExpense) per account in the **account's own currency**. Read in O(1)
//  by AccountDetailView and AccountAggregatesCalculator.
//
//  Same delta-patching pattern as `categoryAggregatesByKey`:
//  • added   → +amount(s) for source / target legs
//  • removed → −amount(s) for source / target legs
//  • updated → bucket-affecting fields trigger remove+add; otherwise no-op
//
//  All currency conversion happens here, at apply-time, via `CurrencyConverter.convertSync`.
//  When the rate cache is cold the patch is skipped and the index is marked stale —
//  reconcile on the next `bumpCurrencyRatesVersion`, same as the category path.
//

import Foundation

extension TransactionStore {

    // MARK: - Public maintenance (called from updateState)

    internal func accountAggregatesAdd(_ tx: Transaction) {
        applyAccountAggregateDelta(tx: tx, sign: 1)
        scheduleAccountAggregatePersist()
    }

    internal func accountAggregatesRemove(_ tx: Transaction) {
        applyAccountAggregateDelta(tx: tx, sign: -1)
        scheduleAccountAggregatePersist()
    }

    internal func accountAggregatesUpdate(old: Transaction, new: Transaction) {
        // Bucket-affecting fields → remove+add. Everything else is a no-op.
        // `convertedAmount` values a cross-currency source leg (recordedAmount); `date`
        // decides whether the transaction is realized yet.
        let bucketAffecting = old.amount != new.amount
            || old.currency != new.currency
            || old.convertedAmount != new.convertedAmount
            || old.date != new.date
            || old.targetAmount != new.targetAmount
            || old.targetCurrency != new.targetCurrency
            || old.type != new.type
            || old.accountId != new.accountId
            || old.targetAccountId != new.targetAccountId
        guard bucketAffecting else { return }
        applyAccountAggregateDelta(tx: old, sign: -1)
        applyAccountAggregateDelta(tx: new, sign: 1)
        scheduleAccountAggregatePersist()
    }

    // MARK: - Persistence

    /// Seed `accountAggregatesByAccountId` from a pre-loaded CoreData snapshot.
    /// Warm-start path: skip the O(N_tx) rebuild walk in `loadData`.
    internal func seedAccountAggregates(from snapshot: [String: AccountAggregates]) {
        accountAggregatesByAccountId = snapshot
        aggregateMapsGeneration &+= 1
    }

    /// Schedule a debounced persist of the current aggregate snapshot to CoreData.
    /// Skipped during `isImporting` — caller flushes via `flushAccountAggregatePersist()`.
    internal func scheduleAccountAggregatePersist() {
        guard !isImporting else { return }
        accountAggregatePersistTask?.cancel()
        accountAggregatePersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            await self.flushAccountAggregatePersist()
        }
    }

    /// Immediate persist (use after wholesale rebuild and from `finishImport()`).
    /// Awaits the actual CoreData write so it is ordered after the raw-transaction
    /// save in `finishImport` — a kill in between would otherwise leave warm-start
    /// aggregates lagging the persisted transactions (M-14). This runs once at
    /// import/rebuild end (after `isImporting = false`), NOT in the per-row hot
    /// loop, so awaiting it does not affect the import hot path.
    internal func flushAccountAggregatePersist() async {
        let snapshot = accountAggregatesToPersist()
        let isWholeMap = hasCompletedInitialLoad
        var currencyById: [String: String] = [:]
        currencyById.reserveCapacity(accounts.count)
        for acc in accounts { currencyById[acc.id] = acc.currency }
        await repository.saveAccountAggregatesSync(snapshot, currencyByAccountId: currencyById)
        // The table now holds totals of the current rule. Before the full load it was
        // emptied instead, and the next load rebuilds it anyway.
        if isWholeMap {
            UserDefaults.standard.set(Self.accountAggregatesRuleVersion, forKey: Self.accountAggregatesRuleVersionKey)
        }
    }

    // MARK: - Valuation rule version

    /// Version of the rule that values a leg in its account's currency. Totals persisted
    /// under an older rule are rebuilt once by the next full load (`loadData`), instead of
    /// mixing with deltas of the new one (a removal would subtract another value than was
    /// added, and the totals would not show the new rule until some other rebuild).
    /// - 2 (2026-10): a cross-currency leg counts the conversion recorded with the
    ///   transaction (`TransactionConversion.recordedAmount`) before today's rate.
    static let accountAggregatesRuleVersion = 2
    static let accountAggregatesRuleVersionKey = "accountAggregates.ruleVersion"

    /// Whether the account totals in CoreData were computed under the current rule.
    static var persistedAccountAggregatesFollowCurrentRule: Bool {
        UserDefaults.standard.integer(forKey: accountAggregatesRuleVersionKey) >= accountAggregatesRuleVersion
    }

    /// What a flush writes; see `categoryAggregatesToPersist`. Before the full load the map
    /// holds only the accounts touched since launch, and the whole-table save would drop
    /// every other account's totals from the warm start. Empty instead: the next full load
    /// rebuilds them from the transactions.
    internal func accountAggregatesToPersist() -> [String: AccountAggregates] {
        hasCompletedInitialLoad ? accountAggregatesByAccountId : [:]
    }

    // MARK: - Cold Rebuild

    /// One-shot O(N_tx) rebuild from the canonical `transactions` array, synchronously.
    /// The day-rollover and FX rebuilds run the same builder off the main actor instead
    /// (`rebuildRealizedAggregates()`). Runs the cold-load builder
    /// (`computeAccountAggregates`, same rule as `applyAccountAggregateDelta`) with one rate
    /// snapshot and schedules ONE persist (the delta loop it replaces persisted nothing).
    internal func rebuildAccountAggregates() {
        let (aggregates, fxStale) = Self.computeAccountAggregates(
            transactions: transactions,
            parsedDates: Self.completedParsedDates(transactions, seed: parsedDateByDateString),
            accountsCurrencyById: accountCurrencyById(),
            rates: RateSnapshot()
        )
        accountAggregatesByAccountId = aggregates
        // Own flag, never cleared here (cache audit #12): the category rebuild owns the reset.
        if fxStale { aggregatesAreFXStale = true }
        aggregateMapsGeneration &+= 1
        scheduleAccountAggregatePersist()
    }

    /// Account id → currency, from `accountById` (what `applyAccountAggregateDelta` reads).
    internal func accountCurrencyById() -> [String: String] {
        var currencyById: [String: String] = [:]
        currencyById.reserveCapacity(accountById.count)
        for (id, account) in accountById { currencyById[id] = account.currency }
        return currencyById
    }

    /// `accountAggregatesRemove` for many rows (`.bulkDeleted`): the same delta per row,
    /// ONE debounced persist instead of a persist Task per row.
    internal func accountAggregatesRemoveBulk(_ txs: [Transaction]) {
        guard !txs.isEmpty else { return }
        for tx in txs {
            applyAccountAggregateDelta(tx: tx, sign: -1)
        }
        scheduleAccountAggregatePersist()
    }

    // MARK: - Private

    /// Mirrors the legacy O(N_tx) loop inside `AccountAggregatesCalculator.compute`
    /// but applied as a delta. Income / expense semantics per transaction type stay
    /// identical so the resulting aggregates are byte-for-byte equivalent.
    private func applyAccountAggregateDelta(tx: Transaction, sign: Int) {
        // Realized actuals only: exclude future-dated tx so the income/expense
        // totals stay consistent with the balance (which also excludes them).
        // Same single rule as `BalanceCalculationEngine.affectsCurrentBalance`.
        let parsedDate = parsedDateByDateString[tx.date] ?? FastDateParser.date(from: tx.date)
        guard LedgerPolicyRule.isRealized(parsedDate) else { return }

        let signD = Double(sign)
        let sourceId = tx.accountId
        let targetId = tx.targetAccountId

        // Source-leg contribution
        if let id = sourceId,
           let currency = accountById[id]?.currency {
            let amt = convertedSourceAmount(tx: tx, to: currency)
            patchBucket(accountId: id, deltaCount: sign, sourceFor: tx, signedAmount: amt * signD)
        }

        // Target-leg contribution (transfers / loan / deposit ops)
        if let id = targetId, id != sourceId,
           let currency = accountById[id]?.currency {
            let amt = convertedTargetAmount(tx: tx, to: currency)
            patchBucket(accountId: id, deltaCount: sign, targetFor: tx, signedAmount: amt * signD)
        }
    }

    private func patchBucket(
        accountId: String,
        deltaCount: Int,
        sourceFor tx: Transaction,
        signedAmount: Double
    ) {
        let existing = accountAggregatesByAccountId[accountId]
            ?? AccountAggregates(totalTransactions: 0, totalIncome: 0, totalExpense: 0)
        var income = existing.totalIncome
        var expense = existing.totalExpense
        let count = existing.totalTransactions + deltaCount

        switch tx.type {
        case .income:
            income += signedAmount
        case .expense:
            expense += signedAmount
        case .internalTransfer:
            expense += signedAmount
        case .depositTopUp:
            expense += signedAmount
        case .depositWithdrawal:
            expense += signedAmount
        case .depositInterestAccrual:
            income += signedAmount
        case .loanPayment, .loanEarlyRepayment:
            expense += signedAmount
        }
        accountAggregatesByAccountId[accountId] = AccountAggregates(
            totalTransactions: max(count, 0),
            totalIncome: income,
            totalExpense: expense
        )
    }

    private func patchBucket(
        accountId: String,
        deltaCount: Int,
        targetFor tx: Transaction,
        signedAmount: Double
    ) {
        let existing = accountAggregatesByAccountId[accountId]
            ?? AccountAggregates(totalTransactions: 0, totalIncome: 0, totalExpense: 0)
        var income = existing.totalIncome
        var expense = existing.totalExpense
        let count = existing.totalTransactions + deltaCount

        switch tx.type {
        case .income:
            // Target leg of an income tx is unusual; mirror existing calculator (no-op).
            break
        case .expense:
            break
        case .internalTransfer:
            income += signedAmount
        case .depositTopUp:
            income += signedAmount
        case .depositWithdrawal:
            income += signedAmount
        case .depositInterestAccrual:
            income += signedAmount
        case .loanPayment, .loanEarlyRepayment:
            expense += signedAmount
        }
        accountAggregatesByAccountId[accountId] = AccountAggregates(
            totalTransactions: max(count, 0),
            totalIncome: income,
            totalExpense: expense
        )
    }

    // MARK: - Currency conversion (account currency)

    /// The source leg in its account's currency: the conversion recorded with the
    /// transaction, the amount its balance moved by (`TransactionConversion.recordedAmount`).
    /// Today's rate only when it holds none; it used to be today's rate always, so a 100 $
    /// expense saved at 450 ₸ moved the balance by 45 000 ₸ and the total by 52 000 ₸.
    private func convertedSourceAmount(tx: Transaction, to: String) -> Double {
        TransactionConversion.recordedAmount(of: tx, inAccountCurrency: to)
            ?? convertedAtCachedRate(tx: tx, to: to)
    }

    private func convertedAtCachedRate(tx: Transaction, to: String) -> Double {
        if tx.currency == to { return tx.amount }
        if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: to) {
            return fx
        }
        // Cold FX cache. Mark stale (own flag, not relying on the category path) so the
        // next bumpCurrencyRatesVersion rebuilds these aggregates too (cache audit #12).
        aggregatesAreFXStale = true
        return tx.convertedAmount ?? tx.amount
    }

    private func convertedTargetAmount(tx: Transaction, to: String) -> Double {
        // Internal transfer with explicit targetAmount in targetCurrency
        if tx.type == .internalTransfer,
           let targetAmount = tx.targetAmount,
           let targetCurrency = tx.targetCurrency {
            if targetCurrency == to { return targetAmount }
            if let fx = CurrencyConverter.convertSync(amount: targetAmount, from: targetCurrency, to: to) {
                return fx
            }
            aggregatesAreFXStale = true
            return targetAmount
        }
        // Not the source leg's recorded conversion: that one is in the source's currency.
        return convertedAtCachedRate(tx: tx, to: to)
    }
}
