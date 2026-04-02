//
//  TransactionEntity+SectionKey.swift
//  AIFinanceManager
//
//  Created on 2026-02-23
//  Task 9: NSFetchedResultsController section grouping support
//  Updated 2026-02-24: dateSectionKey promoted to stored attribute (v3 model)
//
//  Design:
//  - dateSectionKey is a stored String attribute in the CoreData model (v3+).
//  - willSave() auto-populates it whenever `date` changes, including on insert.
//  - The guard against `dateSectionKey == newKey` prevents willSave() recursion
//    (setting a value marks the object dirty → willSave would loop without this check).
//  - AppCoordinator.backfillDateSectionKeysIfNeeded() handles the one-time migration
//    of existing records (dateSectionKey was transient in v1, stored from v3).
//

import CoreData

extension TransactionEntity {

    /// Auto-populates the stored `dateSectionKey` whenever this object is about to be saved.
    ///
    /// CoreData calls `willSave()` on the context's queue (not necessarily the main thread),
    /// so this override is `nonisolated` to match `NSManagedObject.willSave()`.
    /// `@NSManaged` properties use CoreData's KVC machinery which is context-queue-safe.
    ///
    /// The `dateSectionKey != newKey` guard breaks the recursion: setting the property
    /// marks the object dirty (triggering another `willSave()`), but the second call
    /// finds the value already correct and skips the assignment.
    override public nonisolated func willSave() {
        super.willSave()
        // Skip for deletions — no point updating a value about to be removed.
        guard !isDeleted else { return }
        let newKey = self.date.map { TransactionSectionKeyFormatter.string(from: $0) } ?? "0000-00-00"
        if dateSectionKey != newKey {
            dateSectionKey = newKey
        }
    }
}

// MARK: - TransactionSectionKeyFormatter

/// Thread-safe formatter for "YYYY-MM-DD" section key strings.
///
/// Uses Calendar component extraction instead of DateFormatter because
/// `willSave()` runs on CoreData's background queue — DateFormatter is NOT
/// thread-safe and the old shared static instance was a data-race P0.
enum TransactionSectionKeyFormatter: Sendable {
    private nonisolated static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    nonisolated static func string(from date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
