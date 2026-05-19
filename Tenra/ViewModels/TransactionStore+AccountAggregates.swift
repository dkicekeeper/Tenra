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
        let bucketAffecting = old.amount != new.amount
            || old.currency != new.currency
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
    internal func flushAccountAggregatePersist() async {
        let snapshot = accountAggregatesByAccountId
        var currencyById: [String: String] = [:]
        currencyById.reserveCapacity(accounts.count)
        for acc in accounts { currencyById[acc.id] = acc.currency }
        repository.saveAccountAggregates(snapshot, currencyByAccountId: currencyById)
    }

    // MARK: - Cold Rebuild

    /// One-shot O(N_tx) rebuild from the canonical `transactions` array.
    /// Called on cold start and on `updateBaseCurrency` (although account aggregates
    /// are in *account* currency so they're robust to base-currency changes — but
    /// other indexes mirror this signature for consistency).
    internal func rebuildAccountAggregates() {
        accountAggregatesByAccountId.removeAll(keepingCapacity: true)
        accountAggregatesByAccountId.reserveCapacity(accounts.count)
        for tx in transactions {
            applyAccountAggregateDelta(tx: tx, sign: 1)
        }
    }

    // MARK: - Private

    /// Mirrors the legacy O(N_tx) loop inside `AccountAggregatesCalculator.compute`
    /// but applied as a delta. Income / expense semantics per transaction type stay
    /// identical so the resulting aggregates are byte-for-byte equivalent.
    private func applyAccountAggregateDelta(tx: Transaction, sign: Int) {
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

    private func convertedSourceAmount(tx: Transaction, to: String) -> Double {
        if tx.currency == to { return tx.amount }
        if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: to) {
            return fx
        }
        // Cold FX cache. Last-resort fallback matches the legacy calculator —
        // a future bumpCurrencyRatesVersion will trigger a full rebuild.
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
            return targetAmount
        }
        return convertedSourceAmount(tx: tx, to: to)
    }
}
