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

    // MARK: - Load window (see TransactionStore+LoadMerge.swift)

    /// Whether a load may still replace memory. Set by the owning TransactionStore; while
    /// true, changed series and occurrences are recorded so the load keeps them.
    @ObservationIgnored var isProvisional: () -> Bool = { false }
    /// Whether memory holds every series and occurrence. Set by the owning
    /// TransactionStore; the saves below replace whole tables, so until then they are held.
    @ObservationIgnored var holdsCompleteTables: () -> Bool = { true }
    @ObservationIgnored private(set) var seriesChanges = LoadChanges()
    @ObservationIgnored private(set) var occurrenceChanges = LoadChanges()
    @ObservationIgnored private var hasHeldSeriesSave = false
    @ObservationIgnored private var hasHeldOccurrencesSave = false

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
        noteSeriesChanged(series.id)
    }

    func handleSeriesUpdated(old: RecurringSeries, new: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == old.id }) {
            recurringSeries[index] = new
        }
        seriesById[new.id] = new
        noteSeriesChanged(new.id)
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
            noteSeriesChanged(seriesId)
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
        if isProvisional() {
            for id in removedIds { occurrenceChanges.noteDeleted(id) }
        }
        if kept.isEmpty {
            occurrencesBySeriesId.removeValue(forKey: seriesId)
        } else {
            occurrencesBySeriesId[seriesId] = kept
        }
    }

    /// Remove all occurrences for a series (used by deleteSeries).
    /// O(M) lookup + O(N_occ) array filter (rare operation).
    func removeAllOccurrences(for seriesId: String) {
        guard let removed = occurrencesBySeriesId.removeValue(forKey: seriesId) else { return }
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
        if isProvisional() {
            for occurrence in removed { occurrenceChanges.noteDeleted(occurrence.id) }
        }
    }

    func handleSeriesDeleted(seriesId: String) {
        recurringSeries.removeAll { $0.id == seriesId }
        seriesById.removeValue(forKey: seriesId)
        if isProvisional() { seriesChanges.noteDeleted(seriesId) }
        // Note: Transaction cleanup is handled in TransactionStore+Recurring.deleteSeries() before calling apply()
    }

    func appendOccurrences(_ occurrences: [RecurringOccurrence]) {
        recurringOccurrences.append(contentsOf: occurrences)
        for occ in occurrences {
            occurrencesBySeriesId[occ.seriesId, default: []].append(occ)
        }
        if isProvisional() {
            for occ in occurrences { occurrenceChanges.noteChanged(occ.id) }
        }
    }

    private func noteSeriesChanged(_ id: String) {
        if isProvisional() { seriesChanges.noteChanged(id) }
    }

    /// The fetched series and occurrences with the ones changed in memory folded in
    /// (`LoadChanges.merge`). Called by `TransactionStore.loadData` before `load`.
    func mergingRecordedChanges(
        series loadedSeries: [RecurringSeries],
        occurrences loadedOccurrences: [RecurringOccurrence]
    ) -> (series: [RecurringSeries], occurrences: [RecurringOccurrence]) {
        let series = seriesChanges.merge(
            into: loadedSeries,
            changedRows: seriesChanges.changedIds.compactMap { seriesById[$0] },
            id: \.id
        )
        var changedOccurrences: [RecurringOccurrence] = []
        if !occurrenceChanges.changedIds.isEmpty {
            let wanted = Set(occurrenceChanges.changedIds)
            var byId: [String: RecurringOccurrence] = [:]
            for occurrence in recurringOccurrences where wanted.contains(occurrence.id) {
                byId[occurrence.id] = occurrence
            }
            changedOccurrences = occurrenceChanges.changedIds.compactMap { byId[$0] }
        }
        let occurrences = occurrenceChanges.merge(
            into: loadedOccurrences,
            changedRows: changedOccurrences,
            id: \.id
        )
        return (series, occurrences)
    }

    /// Forgets the recorded changes once a load has merged them.
    func clearRecordedChanges() {
        seriesChanges = LoadChanges()
        occurrenceChanges = LoadChanges()
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
            self.writeOccurrences()
        }
    }

    /// Synchronously flush any pending writes. Called from
    /// `TransactionStore.finishImport()` so bulk imports persist deterministically.
    func flushPersist() {
        occurrencesPersistTask?.cancel()
        seriesPersistTask?.cancel()
        writeOccurrences()
        writeSeries()
    }

    func saveSeries() {
        seriesPersistTask?.cancel()
        seriesPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.writeSeries()
        }
    }

    /// Runs the saves held while memory did not hold every series and occurrence.
    func runHeldSaves() {
        if hasHeldOccurrencesSave { writeOccurrences() }
        if hasHeldSeriesSave { writeSeries() }
    }

    private func writeOccurrences() {
        guard holdsCompleteTables() else {
            hasHeldOccurrencesSave = true
            return
        }
        hasHeldOccurrencesSave = false
        repository.saveRecurringOccurrences(recurringOccurrences)
    }

    private func writeSeries() {
        guard holdsCompleteTables() else {
            hasHeldSeriesSave = true
            return
        }
        hasHeldSeriesSave = false
        repository.saveRecurringSeries(recurringSeries)
    }

    func invalidateCacheFor(seriesId: String) {
        for horizon in [1, 3, 6, 12] {
            recurringCache.remove("\(seriesId)_\(horizon)")
        }
    }
}
