//
//  RecurringStore.swift
//  AIFinanceManager
//
//  Phase 03-PERF-02: Extracted from TransactionStore (1213 LOC monolith — first split step).
//  Owns recurring state: series, occurrences, generator, validator, cache.
//  TransactionStore holds a `let recurringStore: RecurringStore` and delegates recurring ops.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class RecurringStore {

    // MARK: - Logger
    private static let logger = Logger(subsystem: "AIFinanceManager", category: "RecurringStore")

    // MARK: - Observable State

    /// All recurring series (subscriptions and generic recurring transactions)
    private(set) var recurringSeries: [RecurringSeries] = []

    /// All recurring occurrences — tracks which transactions were generated from which series
    private(set) var recurringOccurrences: [RecurringOccurrence] = []

    // MARK: - Dependencies

    @ObservationIgnored let recurringGenerator: RecurringTransactionGenerator
    @ObservationIgnored let recurringValidator: RecurringValidationService
    @ObservationIgnored let recurringCache: LRUCache<String, [Transaction]>
    @ObservationIgnored private let repository: DataRepositoryProtocol

    // MARK: - Init

    init(repository: DataRepositoryProtocol, cacheCapacity: Int = 100) {
        self.repository = repository
        self.recurringGenerator = RecurringTransactionGenerator(dateFormatter: DateFormatters.dateFormatter)
        self.recurringValidator = RecurringValidationService()
        self.recurringCache = LRUCache<String, [Transaction]>(capacity: cacheCapacity)
    }

    // MARK: - Data Loading

    /// Load recurring series and occurrences from repository.
    /// Called by TransactionStore.loadData() as part of the background load.
    func load(series: [RecurringSeries], occurrences: [RecurringOccurrence]) {
        recurringSeries = series
        recurringOccurrences = occurrences
    }

    // MARK: - State Mutation Helpers (called by TransactionStore.updateState)

    func handleSeriesCreated(_ series: RecurringSeries) {
        recurringSeries.append(series)
    }

    func handleSeriesUpdated(old: RecurringSeries, new: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == old.id }) {
            recurringSeries[index] = new
        }
        // Note: Transaction regeneration is handled in TransactionStore+Recurring.updateSeries()
    }

    func handleSeriesStopped(seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            var updatedSeries = recurringSeries[index]
            updatedSeries.isActive = false
            // For subscriptions: set status → .paused so that SubscriptionDetailView
            // shows "Resume" instead of "Pause" after stopping from history.
            if updatedSeries.kind == .subscription {
                updatedSeries.status = .paused
            }
            recurringSeries[index] = updatedSeries
        }
        // Transaction cleanup is performed in TransactionStore+Recurring.stopSeries()
        // BEFORE apply(.seriesStopped) is called — via individual apply(.deleted) events.
    }

    /// Remove future occurrences for a series after the given cutoff date (exclusive).
    /// Called by TransactionStore.stopSeries() before apply(.seriesStopped) so that
    /// persistIncremental's saveOccurrences() persists the pruned list.
    func removeOccurrences(seriesId: String, afterDate cutoff: Date) {
        let formatter = DateFormatters.dateFormatter
        recurringOccurrences.removeAll { occ in
            guard occ.seriesId == seriesId else { return false }
            guard let date = formatter.date(from: occ.occurrenceDate) else { return false }
            return date > cutoff
        }
    }

    /// Remove all occurrences for a series (used by deleteSeries).
    func removeAllOccurrences(for seriesId: String) {
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
    }

    func handleSeriesDeleted(seriesId: String) {
        recurringSeries.removeAll { $0.id == seriesId }
        // Note: Transaction cleanup is handled in TransactionStore+Recurring.deleteSeries() before calling apply()
    }

    func appendOccurrences(_ occurrences: [RecurringOccurrence]) {
        recurringOccurrences.append(contentsOf: occurrences)
    }

    func saveOccurrences() {
        repository.saveRecurringOccurrences(recurringOccurrences)
    }

    func saveSeries() {
        repository.saveRecurringSeries(recurringSeries)
    }

    func invalidateCacheFor(seriesId: String) {
        for horizon in [1, 3, 6, 12] {
            recurringCache.remove("\(seriesId)_\(horizon)")
        }
    }
}
