//
//  TransactionPaginationController.swift
//  AIFinanceManager
//
//  Created on 2026-02-23
//  Task 9: Paginated, sectioned transaction access via NSFetchedResultsController
//  Updated 2026-02-24: dateSectionKey promoted to stored attribute (CoreData model v3)
//
//  Design decisions:
//  - TransactionStore remains SSOT for mutations; this controller is read-only.
//  - fetchBatchSize = 50: only visible batch is materialized in memory (vs all 19k).
//  - sectionNameKeyPath = "dateSectionKey": SQL-level GROUP BY on the stored column —
//    performFetch() is O(M sections) not O(N objects). Previously "dateSectionKey" was
//    transient, forcing FRC to fault-in ALL 19k objects to compute section keys (~10s).
//    Promoting it to a stored attribute reduces the initial fetch to <50ms.
//  - cacheName = nil: the FRC on-disk section cache is invalidated on model migration
//    anyway; omitting it removes a stale-cache footgun with no measurable latency cost
//    because the stored column lets SQLite compute sections in one round-trip.
//  - Filters trigger applyCurrentFilters() + performFetch().
//

import Foundation
import CoreData
import Observation
import os
import QuartzCore

// MARK: - Supporting Types

/// A single date-grouped section of transactions for display in a list.
struct TransactionSection: Identifiable {
    /// "YYYY-MM-DD" — unique per calendar day, doubles as the section identifier.
    let id: String
    /// Human-readable date string (same value as id; views may format it further).
    let date: String
    /// Pre-computed count from the FRC section — O(1), no entity materialization.
    let numberOfObjects: Int

    /// Lazily convert section objects to Transaction value types.
    /// Only called when SwiftUI renders this section's rows — defers O(N) work
    /// to scroll time instead of blocking the main thread during rebuildSections().
    var transactions: [Transaction] {
        (sectionInfo.objects as? [TransactionEntity] ?? [])
            .compactMap { entity -> Transaction? in
                // Guard: skip objects that were deleted before sections could be rebuilt.
                // isDeleted is safe to read without firing a CoreData fault — it checks
                // the context's deletedObjects set, not the persistent store.
                guard !entity.isDeleted else { return nil }
                return entity.toTransaction()
            }
    }

    // Internal: NSFetchedResultsSectionInfo is a class, so this is a reference —
    // no copy overhead despite TransactionSection being a value type.
    fileprivate let sectionInfo: any NSFetchedResultsSectionInfo
}

// MARK: - TransactionPaginationController

/// Manages paginated, sectioned transaction display via NSFetchedResultsController.
///
/// Exposes `sections` and `totalCount` as observable state consumed by SwiftUI views.
/// Setting any filter property automatically re-fetches and updates the observable state.
///
/// TransactionStore remains the single source of truth for all mutations.
/// This class is purely a read-optimized presentation layer over CoreData.
@Observable @MainActor
final class TransactionPaginationController: NSObject {

    // MARK: - Observable State

    /// Date-sectioned transactions ready for list display.
    private(set) var sections: [TransactionSection] = []

    /// Total number of transactions matching current filters (pre-pagination).
    private(set) var totalCount: Int = 0

    // MARK: - Filters
    // Each didSet invalidates the FRC cache and triggers a re-fetch.

    var searchQuery: String = "" {
        didSet { if searchQuery != oldValue { scheduleFilterUpdate() } }
    }

    var selectedAccountId: String? {
        didSet { if selectedAccountId != oldValue { scheduleFilterUpdate() } }
    }

    var selectedCategoryId: String? {
        didSet { if selectedCategoryId != oldValue { scheduleFilterUpdate() } }
    }

    var selectedType: TransactionType? {
        didSet { if selectedType != oldValue { scheduleFilterUpdate() } }
    }

    var dateRange: (start: Date, end: Date)? {
        didSet {
            let changed: Bool
            switch (oldValue, dateRange) {
            case (.none, .none): changed = false
            case (.some(let old), .some(let new)):
                changed = old.start != new.start || old.end != new.end
            default: changed = true
            }
            if changed { scheduleFilterUpdate() }
        }
    }

    // MARK: - Private

    @ObservationIgnored private var frc: NSFetchedResultsController<TransactionEntity>?
    @ObservationIgnored private let stack: CoreDataStack
    @ObservationIgnored private let logger = Logger(
        subsystem: "AIFinanceManager",
        category: "TransactionPaginationController"
    )
    /// When true, individual filter property didSet observers skip scheduleFilterUpdate.
    /// batchUpdateFilters() sets this flag, applies all changes, then calls scheduleFilterUpdate once.
    @ObservationIgnored private var isBatchUpdating = false

    /// Observer token for CoreDataStack.storeDidResetNotification.
    @ObservationIgnored private var storeResetObserver: NSObjectProtocol?

    // MARK: - Init

    init(stack: CoreDataStack) {
        self.stack = stack
        super.init()
        observeStoreReset()
    }

    deinit {
        if let observer = storeResetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Store Reset Handling

    /// Listen for persistent store replacement (resetAllData) so we can tear down
    /// the old FRC — whose internal state references the destroyed store UUID —
    /// and re-create it on the new store before any merge triggers the delegate.
    private func observeStoreReset() {
        storeResetObserver = NotificationCenter.default.addObserver(
            forName: CoreDataStack.storeDidResetNotification,
            object: stack,
            queue: nil // synchronous on posting thread (main) — MUST run before any subsequent save+merge
        ) { [weak self] _ in
            // resetAllData() is always called from @MainActor context,
            // so this closure runs on the main thread.
            MainActor.assumeIsolated {
                self?.handleStoreReset()
            }
        }
    }

    /// Tear down the old FRC and re-create it on the (new) persistent store.
    /// Called synchronously from the storeDidReset notification handler.
    private func handleStoreReset() {
        guard frc != nil else { return } // setup() hasn't been called yet
        logger.debug("🔄 [FRC] handleStoreReset — tearing down old FRC and recreating on new store")
        frc?.delegate = nil
        frc = nil
        sections = []
        totalCount = 0
        setup()
    }

    // MARK: - Setup

    /// Configures the NSFetchedResultsController and performs the initial fetch.
    /// Must be called once after initialisation (called by AppCoordinator.initialize()).
    func setup() {
        let t_setup = CACurrentMediaTime()
        logger.debug("📋 [FRC] setup() START")

        let request = TransactionEntity.fetchRequest()
        // Sort descending by date so newest transactions appear first.
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        // Fetch in batches of 50 — only rows visible on screen are faulted into memory.
        request.fetchBatchSize = 50
        // Keep objects as faults until their properties are accessed.
        request.returnsObjectsAsFaults = true

        let viewContext = stack.viewContext
        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: viewContext,
            sectionNameKeyPath: "dateSectionKey",  // stored attribute → SQL GROUP BY, O(M)
            cacheName: nil  // no on-disk cache; stored column makes re-fetch cheap anyway
        )
        frc?.delegate = self
        performFetch()
        let elapsed = CACurrentMediaTime() - t_setup
        logger.debug("📋 [FRC] setup() DONE in \(String(format: "%.0f", elapsed*1000))ms — sections:\(self.sections.count) totalCount:\(self.totalCount)")
    }

    // MARK: - Filter Application

    private func scheduleFilterUpdate() {
        guard frc != nil else { return }
        // Skip intermediate rebuilds while a batch filter update is in progress.
        // batchUpdateFilters() will call scheduleFilterUpdate() once after all changes.
        guard !isBatchUpdating else { return }
        applyCurrentFilters()
    }

    // MARK: - Batch Filter Update

    /// Apply multiple filter changes atomically — triggers only one performFetch + rebuildSections.
    ///
    /// Each parameter uses a double-optional convention:
    /// - `nil`         → don't touch this filter (leave it as-is)
    /// - `.some(nil)`  → clear this filter (set it to nil)
    /// - `.some(value)` → set this filter to value
    ///
    /// Using this method instead of setting individual properties prevents the 4×
    /// redundant performFetch() + rebuildSections() calls that occur when properties
    /// are assigned sequentially (each didSet triggers scheduleFilterUpdate).
    func batchUpdateFilters(
        searchQuery: String? = nil,
        selectedAccountId: String?? = nil,
        selectedCategoryId: String?? = nil,
        selectedType: TransactionType?? = nil,
        dateRange: (start: Date, end: Date)?? = nil
    ) {
        isBatchUpdating = true

        if let q = searchQuery { self.searchQuery = q }
        if let a = selectedAccountId { self.selectedAccountId = a }
        if let c = selectedCategoryId { self.selectedCategoryId = c }
        if let t = selectedType { self.selectedType = t }
        if let d = dateRange { self.dateRange = d }

        // Must set to false BEFORE calling scheduleFilterUpdate so the
        // guard !isBatchUpdating check inside passes.
        isBatchUpdating = false
        // Single fetch + rebuild after all filter changes are applied.
        scheduleFilterUpdate()
    }

    private func applyCurrentFilters() {
        var predicates: [NSPredicate] = []

        if !searchQuery.isEmpty {
            let q = searchQuery
            predicates.append(NSPredicate(
                format: "descriptionText CONTAINS[cd] %@ OR category CONTAINS[cd] %@",
                q, q
            ))
        }

        if let accountId = selectedAccountId {
            predicates.append(NSPredicate(format: "accountId == %@", accountId))
        }

        if let categoryId = selectedCategoryId {
            // category stores the category name/id string on TransactionEntity
            predicates.append(NSPredicate(format: "category == %@", categoryId))
        }

        if let type = selectedType {
            predicates.append(NSPredicate(format: "type == %@", type.rawValue))
        }

        if let range = dateRange {
            predicates.append(NSPredicate(
                format: "date >= %@ AND date <= %@",
                range.start as NSDate,
                range.end as NSDate
            ))
        }

        let newPredicate: NSPredicate? = predicates.isEmpty
            ? nil
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // Skip the SQLite round-trip if the effective predicate hasn't changed.
        // This avoids a redundant performFetch() each time HistoryView appears
        // (handleOnAppear + setupInitialFilters both call applyFiltersToController
        // with the same nil-predicate that setup() already established).
        let newFormat = newPredicate?.predicateFormat
        let currentFormat = frc?.fetchRequest.predicate?.predicateFormat
        guard newFormat != currentFormat else { return }

        frc?.fetchRequest.predicate = newPredicate
        performFetch()
    }

    // MARK: - Fetch Execution

    private func performFetch() {
        guard let frc else {
            logger.debug("⚠️  [FRC] performFetch() skipped — frc is nil (setup() not yet called)")
            return
        }
        let t0 = CACurrentMediaTime()
        let predDesc = frc.fetchRequest.predicate?.predicateFormat ?? "<no predicate>"
        logger.debug("🔍 [FRC] performFetch() START — predicate: \(predDesc)")
        do {
            try frc.performFetch()
            let t1 = CACurrentMediaTime()
            let objectCount = frc.fetchedObjects?.count ?? 0
            let sectionCount = frc.sections?.count ?? 0
            logger.debug("🔍 [FRC] frc.performFetch() DONE in \(String(format: "%.0f", (t1-t0)*1000))ms — \(objectCount) objects, \(sectionCount) sections")
            rebuildSections()
            let t2 = CACurrentMediaTime()
            logger.debug("🔍 [FRC] performFetch()+rebuildSections() total: \(String(format: "%.0f", (t2-t0)*1000))ms")
        } catch {
            logger.error("FRC performFetch failed: \(error.localizedDescription)")
        }
    }

    private func rebuildSections() {
        guard let frcSections = frc?.sections else {
            sections = []
            totalCount = 0
            return
        }

        let t0 = CACurrentMediaTime()
        // O(M) — only stores section metadata + a reference to the NSFetchedResultsSectionInfo.
        // toTransaction() is deferred to TransactionSection.transactions (computed property),
        // which SwiftUI calls lazily only for the sections currently rendered on screen.
        sections = frcSections.map { section in
            TransactionSection(
                id: section.name,
                date: section.name,
                numberOfObjects: section.numberOfObjects,
                sectionInfo: section
            )
        }
        totalCount = frc?.fetchedObjects?.count ?? 0
        let t1 = CACurrentMediaTime()
        logger.debug("🗂️  [FRC] rebuildSections() DONE in \(String(format: "%.0f", (t1-t0)*1000))ms — \(self.sections.count) sections, \(self.totalCount) total")
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension TransactionPaginationController: NSFetchedResultsControllerDelegate {
    /// Called on the main thread (viewContext is a main-thread context, so
    /// automaticallyMergesChangesFromParent fires the FRC delegate on the main thread).
    ///
    /// CRITICAL: rebuildSections() MUST be called synchronously here via
    /// MainActor.assumeIsolated — NOT via Task { @MainActor in }.
    ///
    /// The async Task hop creates a window where a pending CADisplayLink frame
    /// (SwiftUI render) runs BEFORE rebuildSections() updates `sections`. During
    /// that window, SwiftUI renders with the OLD sections array, which may contain
    /// sectionInfo objects referencing deleted TransactionEntity rows. Accessing
    /// those rows fires a CoreData fault that crashes with
    /// "persistent store is not reachable from this NSManagedObjectContext's coordinator".
    nonisolated func controllerDidChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        let t = CACurrentMediaTime()
        // Safe: viewContext is main-thread affined, so this delegate is always called
        // on the main thread. assumeIsolated is a zero-overhead runtime assertion.
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            let delay = CACurrentMediaTime() - t
            self.logger.debug("🔔 [FRC] controllerDidChangeContent fired (sync, delay: \(String(format: "%.0f", delay*1000))ms) — rebuilding sections")
            self.rebuildSections()
        }
    }
}
