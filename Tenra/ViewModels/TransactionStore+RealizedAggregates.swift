//
//  TransactionStore+RealizedAggregates.swift
//  Tenra
//
//  Full rebuild of the realized aggregates — `transactionIdsByCategoryName`,
//  `categoryAggregatesByKey`, `accountAggregatesByAccountId` — off the main actor.
//
//  Runs when a future-dated transaction comes due (`recalculateLedgerIfDayChanged`) and
//  when FX rates heal aggregates built against a cold rate cache
//  (`bumpCurrencyRatesVersion`). Both used to rebuild on the main actor: a DateFormatter
//  parse and a `startOfDay` per transaction, and a debounced-persist Task created per
//  transaction (~19k Tasks queued on main) — a 0.6–0.9 s freeze just after Home appeared
//  or on foreground, repeated on every rate update while `aggregatesAreFXStale` stayed set.
//
//  Now the cold-load builders (TransactionStore+LoadSnapshot.swift) run in a detached task
//  over a Sendable copy of the inputs; the main actor only assigns the result and schedules
//  one persist per map. The synchronous `rebuildCategoryIndexes()` /
//  `rebuildAccountAggregates()` run the same builders, so every rebuild path yields the
//  same maps (pinned by RealizedAggregatesRebuildTests against the per-row deltas).
//
//  The store keeps changing while the detached pass runs. Its result is assigned only if
//  nothing it depends on changed meanwhile (`RealizedAggregatesStamp`); otherwise it runs
//  again on fresh inputs. Rebuilds are single-flight: a request made while one runs joins
//  it, which is enough because that pass re-checks the stamp before assigning.
//

import Foundation
import os

private let realizedAggregatesLogger = Logger(subsystem: "Tenra", category: "RealizedAggregates")

extension TransactionStore {

    // MARK: - Types

    /// What one rebuild reads. Built on the main actor in O(N_accounts): the transaction
    /// array and the date cache are copy-on-write, so capturing them retains buffers.
    struct RealizedAggregatesInputs: Sendable {
        let transactions: [Transaction]
        let parsedDateByDateString: [String: Date]
        let baseCurrency: String
        let accountsCurrencyById: [String: String]
    }

    /// What one rebuild produces; assigned wholesale on the main actor.
    struct RealizedAggregates: Sendable {
        let transactionIdsByCategoryName: [String: [String]]
        let categoryAggregates: [String: CategoryAggregate]
        let categoryAggregatesAreFXStale: Bool
        let accountAggregates: [String: AccountAggregates]
        let accountAggregatesAreFXStale: Bool
    }

    /// Every dimension the realized aggregates depend on (CLAUDE.md red flag 12). An
    /// off-main rebuild whose stamp no longer matches when it lands is not assigned.
    struct RealizedAggregatesStamp: Equatable {
        /// Transactions: every `apply` event, and the category-rename rewrite.
        let mutationVersion: Int
        /// Account currencies (account totals are in the account's own currency).
        /// `loadData()` bumps it as well, through `rebuildAccountById()`.
        let accountsMutationVersion: Int
        /// Category CRUD: renames re-key aggregate buckets, deletes drop them.
        let categoriesMutationVersion: Int
        /// FX rates: category totals are converted to the base currency.
        let currencyRatesVersion: Int
        let baseCurrency: String
        /// "Realized" is "dated on or before today" (`LedgerPolicyRule.isRealized`).
        let startOfToday: Date
        /// Other wholesale writes of the aggregate maps (synchronous rebuilds, seeds).
        let aggregateMapsGeneration: Int
        /// Direct assignments of `transactions` (fixtures) bump no version.
        let transactionsCount: Int
    }

    /// Tries before an off-main rebuild gives up on landing on unchanged inputs and
    /// settles on the main actor.
    private static let realizedAggregatesMaxAttempts = 3

    // MARK: - Builders (pure, any actor)

    /// Mirrors `rebuildCategoryIndexes()` + `rebuildAccountAggregates()` exactly: same
    /// eligibility rule, same realized-date gate, same per-type sign tables, one rate table.
    nonisolated static func buildRealizedAggregates(
        from inputs: RealizedAggregatesInputs,
        rates: RateSnapshot
    ) -> RealizedAggregates {
        let parsedDates = completedParsedDates(inputs.transactions, seed: inputs.parsedDateByDateString)
        let (categoryAggregates, categoryFXStale) = computeCategoryAggregates(
            transactions: inputs.transactions,
            parsedDates: parsedDates,
            baseCurrency: inputs.baseCurrency,
            rates: rates
        )
        let (accountAggregates, accountFXStale) = computeAccountAggregates(
            transactions: inputs.transactions,
            parsedDates: parsedDates,
            accountsCurrencyById: inputs.accountsCurrencyById,
            rates: rates
        )
        return RealizedAggregates(
            transactionIdsByCategoryName: categoryNameBuckets(inputs.transactions),
            categoryAggregates: categoryAggregates,
            categoryAggregatesAreFXStale: categoryFXStale,
            accountAggregates: accountAggregates,
            accountAggregatesAreFXStale: accountFXStale
        )
    }

    /// The date cache plus every date string it lacks. Entries are keyed by date string and
    /// never go stale, so the store's map is a valid seed; FastDateParser is pinned to
    /// `DateFormatters.dateFormatter` by FastDateParserTests.
    nonisolated static func completedParsedDates(
        _ transactions: [Transaction],
        seed: [String: Date]
    ) -> [String: Date] {
        var parsed = seed
        for tx in transactions where parsed[tx.date] == nil {
            if let date = FastDateParser.date(from: tx.date) {
                parsed[tx.date] = date
            }
        }
        return parsed
    }

    /// `transactionIdsByCategoryName` in array order, as the per-row rebuild built it.
    nonisolated static func categoryNameBuckets(_ transactions: [Transaction]) -> [String: [String]] {
        var buckets: [String: [String]] = [:]
        buckets.reserveCapacity(64)
        for tx in transactions where isAggregatableForLoad(tx) {
            buckets[tx.category, default: []].append(tx.id)
        }
        return buckets
    }

    // MARK: - Main actor

    func realizedAggregatesInputs() -> RealizedAggregatesInputs {
        RealizedAggregatesInputs(
            transactions: transactions,
            parsedDateByDateString: parsedDateByDateString,
            baseCurrency: baseCurrency,
            accountsCurrencyById: accountCurrencyById()
        )
    }

    func realizedAggregatesStamp() -> RealizedAggregatesStamp {
        RealizedAggregatesStamp(
            mutationVersion: mutationVersion,
            accountsMutationVersion: accountsMutationVersion,
            categoriesMutationVersion: categoriesMutationVersion,
            currencyRatesVersion: currencyRatesVersion,
            baseCurrency: baseCurrency,
            startOfToday: Calendar.current.startOfDay(for: Date()),
            aggregateMapsGeneration: aggregateMapsGeneration,
            transactionsCount: transactions.count
        )
    }

    /// Rebuilds the realized aggregates off the main actor and assigns them on it (one
    /// `categoriesMutationVersion` bump, one persist per map). Returns once the assigned
    /// maps match the store as it is when this returns.
    func rebuildRealizedAggregates() async {
        if let running = realizedAggregatesRebuildTask {
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runRealizedAggregatesRebuild()
        }
        realizedAggregatesRebuildTask = task
        await task.value
    }

    private func runRealizedAggregatesRebuild() async {
        for attempt in 1...Self.realizedAggregatesMaxAttempts {
            let stamp = realizedAggregatesStamp()
            let inputs = realizedAggregatesInputs()
            let result = await Task.detached(priority: .userInitiated) {
                Self.buildRealizedAggregates(from: inputs, rates: RateSnapshot())
            }.value
            if realizedAggregatesStamp() == stamp {
                assignRealizedAggregates(result)
                realizedAggregatesRebuildTask = nil
                return
            }
            realizedAggregatesLogger.debug("inputs changed during rebuild attempt \(attempt, privacy: .public), retrying")
        }
        // Changed under every attempt (e.g. a long burst of edits): settle here so the
        // caller still gets maps that match the store.
        assignRealizedAggregates(Self.buildRealizedAggregates(from: realizedAggregatesInputs(), rates: RateSnapshot()))
        realizedAggregatesRebuildTask = nil
    }

    /// Wholesale assignment. The FX-stale flag is OR'd from both maps (the old day-rollover
    /// path rebuilt account totals first and then let the category rebuild clear the flag).
    private func assignRealizedAggregates(_ result: RealizedAggregates) {
        transactionIdsByCategoryName = result.transactionIdsByCategoryName
        categoryAggregatesByKey = result.categoryAggregates
        accountAggregatesByAccountId = result.accountAggregates
        aggregatesAreFXStale = result.categoryAggregatesAreFXStale || result.accountAggregatesAreFXStale
        aggregateMapsGeneration &+= 1
        categoriesMutationVersion &+= 1
        scheduleAggregatePersist()
        scheduleAccountAggregatePersist()
        realizedAggregatesLogger.info(
            "rebuilt realized aggregates off main: \(result.categoryAggregates.count, privacy: .public) category buckets, \(result.accountAggregates.count, privacy: .public) accounts, fxStale=\(self.aggregatesAreFXStale, privacy: .public)"
        )
    }
}
