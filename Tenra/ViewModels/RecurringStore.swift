//
//  RecurringStore.swift
//  Tenra
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
    private static let logger = Logger(subsystem: "Tenra", category: "RecurringStore")

    // MARK: - Observable State

    /// All recurring series (subscriptions and generic recurring transactions)
    private(set) var recurringSeries: [RecurringSeries] = []

    /// Pre-maintained id → RecurringSeries map for O(1) lookups.
    /// Replaces `recurringSeries.first(where: { $0.id == seriesId })` scans called from
    /// every transaction-card render and from many places in TransactionStore+Recurring.
    /// Sync rule: every mutation in `load`/`handleSeries*` MUST update both arrays together.
    @ObservationIgnored private(set) var seriesById: [String: RecurringSeries] = [:]

    /// All recurring occurrences — tracks which transactions were generated from which series
    private(set) var recurringOccurrences: [RecurringOccurrence] = []

    /// O(1) per-series occurrence lookup. Maintained alongside the `recurringOccurrences`
    /// array on every mutation. Replaces `recurringOccurrences.filter { $0.seriesId == X }`
    /// and `recurringOccurrences.removeAll { $0.seriesId == X }` full scans across N_occ.
    @ObservationIgnored private(set) var occurrencesBySeriesId: [String: [RecurringOccurrence]] = [:]

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
        seriesById = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        recurringOccurrences = occurrences
        rebuildOccurrencesBySeriesId()
    }

    /// One-shot O(N_occ) rebuild from the canonical `recurringOccurrences` array.
    /// Kept internal so the cold-start in `load(...)` and any future
    /// migration paths can use the same code.
    internal func rebuildOccurrencesBySeriesId() {
        var grouped: [String: [RecurringOccurrence]] = [:]
        grouped.reserveCapacity(seriesById.count)
        for occ in recurringOccurrences {
            grouped[occ.seriesId, default: []].append(occ)
        }
        occurrencesBySeriesId = grouped
    }

    // MARK: - State Mutation Helpers (called by TransactionStore.updateState)

    func handleSeriesCreated(_ series: RecurringSeries) {
        recurringSeries.append(series)
        seriesById[series.id] = series
    }

    func handleSeriesUpdated(old: RecurringSeries, new: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == old.id }) {
            recurringSeries[index] = new
        }
        seriesById[new.id] = new
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
            seriesById[seriesId] = updatedSeries
        }
        // Transaction cleanup is performed in TransactionStore+Recurring.stopSeries()
        // BEFORE apply(.seriesStopped) is called — via individual apply(.deleted) events.
    }

    /// Remove future occurrences for a series after the given cutoff date (exclusive).
    /// Called by TransactionStore.stopSeries() before apply(.seriesStopped) so that
    /// persistIncremental's saveOccurrences() persists the pruned list.
    /// O(M) in the series's occurrences, not O(N_occ).
    func removeOccurrences(seriesId: String, afterDate cutoff: Date) {
        guard let seriesBucket = occurrencesBySeriesId[seriesId], !seriesBucket.isEmpty else { return }
        let formatter = DateFormatters.dateFormatter
        let kept = seriesBucket.filter { occ in
            guard let date = formatter.date(from: occ.occurrenceDate) else { return true }
            return date <= cutoff
        }
        guard kept.count != seriesBucket.count else { return }
        // Persist back to canonical array (O(N_occ) walk to drop the removed ids).
        let removedIds = Set(seriesBucket.filter { occ in
            guard let date = formatter.date(from: occ.occurrenceDate) else { return false }
            return date > cutoff
        }.map { $0.id })
        recurringOccurrences.removeAll { removedIds.contains($0.id) }
        if kept.isEmpty {
            occurrencesBySeriesId.removeValue(forKey: seriesId)
        } else {
            occurrencesBySeriesId[seriesId] = kept
        }
    }

    /// Remove all occurrences for a series (used by deleteSeries).
    /// O(M) lookup + O(N_occ) array filter (rare operation).
    func removeAllOccurrences(for seriesId: String) {
        guard occurrencesBySeriesId.removeValue(forKey: seriesId) != nil else { return }
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
    }

    func handleSeriesDeleted(seriesId: String) {
        recurringSeries.removeAll { $0.id == seriesId }
        seriesById.removeValue(forKey: seriesId)
        // Note: Transaction cleanup is handled in TransactionStore+Recurring.deleteSeries() before calling apply()
    }

    func appendOccurrences(_ occurrences: [RecurringOccurrence]) {
        recurringOccurrences.append(contentsOf: occurrences)
        for occ in occurrences {
            occurrencesBySeriesId[occ.seriesId, default: []].append(occ)
        }
    }

    // MARK: - Persistence (debounced)
    //
    // Both `saveOccurrences` and `saveSeries` write the full table on every call.
    // A single recurring-series edit can trigger N append/delete/regenerate cycles
    // (TransactionStore+Recurring) and each one ends with `saveOccurrences()`.
    // Coalesce them into one CoreData write per 300ms burst.

    private var occurrencesPersistTask: Task<Void, Never>?
    private var seriesPersistTask: Task<Void, Never>?

    func saveOccurrences() {
        occurrencesPersistTask?.cancel()
        occurrencesPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.repository.saveRecurringOccurrences(self.recurringOccurrences)
        }
    }

    /// Synchronously flush any pending writes. Called from
    /// `TransactionStore.finishImport()` so bulk imports persist deterministically.
    func flushPersist() {
        occurrencesPersistTask?.cancel()
        seriesPersistTask?.cancel()
        repository.saveRecurringOccurrences(recurringOccurrences)
        repository.saveRecurringSeries(recurringSeries)
    }

    func saveSeries() {
        seriesPersistTask?.cancel()
        seriesPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.repository.saveRecurringSeries(self.recurringSeries)
        }
    }

    func invalidateCacheFor(seriesId: String) {
        for horizon in [1, 3, 6, 12] {
            recurringCache.remove("\(seriesId)_\(horizon)")
        }
    }
}
