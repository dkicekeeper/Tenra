//
//  TransactionStore+LoadMerge.swift
//  Tenra
//
//  Keeps what the user changes while memory is provisional.
//
//  Memory is provisional from launch until the first full load lands (`loadData`),
//  and again while any later load runs (a restore, a reset). In that window:
//
//  • A load replaces memory with rows it fetched before the change. An account or
//    category created right after launch used to vanish when the launch load landed,
//    and the next whole-table save then deleted it from CoreData too.
//    Every change made in the window is recorded here (ids only), and the load folds
//    it into what it fetched: edited rows take their in-memory version, deleted rows
//    are dropped, new rows are appended.
//
//  • Memory may not hold every row. Before the full load the subcategory and link
//    tables, series and occurrences are empty, and saving one of them (each replaces
//    the whole table) deleted every row memory lacked: creating a subcategory in the
//    first seconds wiped the subcategory table. Whole-table saves of a table memory
//    does not fully hold are held, and run once the load has merged.
//
//  Accounts and categories are complete after the fast path (`loadAccountsOnly`);
//  everything else only after `loadData`. App Intents write before the full load on
//  purpose: transactions persist row by row and aggregates have their own guard
//  (`categoryAggregatesToPersist`), and subcategory links go straight to CoreData
//  (`IntentSubcategoryStore`), so none of that waits here.
//

import Foundation

/// Ids of one table's rows changed in memory while a load could overwrite memory.
nonisolated struct LoadChanges: Sendable, Equatable {

    /// Added or edited rows, in the order they first changed.
    private(set) var changedIds: [String] = []
    private var changedIdSet: Set<String> = []
    private(set) var deletedIds: Set<String> = []

    var isEmpty: Bool { changedIds.isEmpty && deletedIds.isEmpty }

    mutating func noteChanged(_ id: String) {
        deletedIds.remove(id)
        if changedIdSet.insert(id).inserted {
            changedIds.append(id)
        }
    }

    mutating func noteDeleted(_ id: String) {
        if changedIdSet.remove(id) != nil {
            changedIds.removeAll { $0 == id }
        }
        deletedIds.insert(id)
    }

    /// `loaded` with these changes applied. `changedRows` are the current in-memory
    /// versions of `changedIds`: rows the load fetched are replaced in place, the others
    /// are appended in the order they first changed. Deleted rows are dropped.
    func merge<Row>(into loaded: [Row], changedRows: [Row], id: (Row) -> String) -> [Row] {
        guard !isEmpty else { return loaded }
        var replacements: [String: Row] = [:]
        replacements.reserveCapacity(changedRows.count)
        for row in changedRows { replacements[id(row)] = row }

        var merged: [Row] = []
        merged.reserveCapacity(loaded.count + changedRows.count)
        var placed = Set<String>()
        for row in loaded {
            let rowId = id(row)
            if deletedIds.contains(rowId) { continue }
            if let replacement = replacements[rowId] {
                if placed.insert(rowId).inserted { merged.append(replacement) }
            } else {
                merged.append(row)
            }
        }
        for row in changedRows where placed.insert(id(row)).inserted {
            merged.append(row)
        }
        return merged
    }
}

/// Every table's `LoadChanges` the transaction store records (series and occurrences are
/// recorded by `RecurringStore`).
nonisolated struct LoadJournal: Sendable {
    var transactions = LoadChanges()
    var accounts = LoadChanges()
    var categories = LoadChanges()
    var subcategories = LoadChanges()
    var categorySubcategoryLinks = LoadChanges()
    var transactionSubcategoryLinks = LoadChanges()
    /// Bumped on every recorded change: a load that saw it move while building its
    /// snapshot merges and builds again.
    var version = 0
}

/// Tables saved whole: a save deletes every row it is not given.
nonisolated enum WholeTable: Hashable, Sendable {
    case accounts
    case categories
    case subcategories
    case categorySubcategoryLinks
    case transactionSubcategoryLinks
    /// Series and occurrences (RecurringStore).
    case recurring
}

extension TransactionStore {

    // MARK: - State

    /// True while a load may still replace memory: before the first full load landed,
    /// and while any load runs. Changes are recorded only then.
    var isLoadProvisional: Bool {
        !hasCompletedInitialLoad || isLoadInFlight
    }

    /// Whether memory holds every row of `table`, so a whole-table save is safe.
    func holdsCompleteTable(_ table: WholeTable) -> Bool {
        guard !isLoadInFlight else { return false }
        switch table {
        case .accounts, .categories:
            return hasCompletedInitialLoad || hasLoadedAccountsAndCategories
        case .subcategories, .categorySubcategoryLinks, .transactionSubcategoryLinks, .recurring:
            return hasCompletedInitialLoad
        }
    }

    /// Returns once no load is running (at once when none is).
    func waitForLoadInFlight() async {
        guard isLoadInFlight else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadWaiters.append(continuation)
        }
    }

    // MARK: - Recording

    /// Records the transactions an event changes. Called first thing in `updateState`.
    func noteProvisionalChange(_ event: TransactionEvent) {
        guard isLoadProvisional else { return }
        switch event {
        case .added(let tx):
            loadJournal.transactions.noteChanged(tx.id)
        case .updated(_, let new):
            loadJournal.transactions.noteChanged(new.id)
        case .deleted(let tx):
            loadJournal.transactions.noteDeleted(tx.id)
        case .bulkAdded(let txs):
            for tx in txs { loadJournal.transactions.noteChanged(tx.id) }
        case .bulkUpdated(let changes):
            for change in changes { loadJournal.transactions.noteChanged(change.new.id) }
        case .bulkDeleted(let txs):
            for tx in txs { loadJournal.transactions.noteDeleted(tx.id) }
        case .seriesCreated, .seriesUpdated, .seriesStopped, .seriesDeleted:
            // RecurringStore records its own rows.
            return
        }
        loadJournal.version &+= 1
    }

    /// Records changed and deleted rows of one table.
    func noteProvisionalChange(
        _ table: WritableKeyPath<LoadJournal, LoadChanges>,
        changed changedIds: [String] = [],
        deleted deletedIds: [String] = []
    ) {
        guard isLoadProvisional, !(changedIds.isEmpty && deletedIds.isEmpty) else { return }
        for id in changedIds { loadJournal[keyPath: table].noteChanged(id) }
        for id in deletedIds { loadJournal[keyPath: table].noteDeleted(id) }
        loadJournal.version &+= 1
    }

    /// Records the difference between two id-keyed versions of a table (`rebuildAccountById`
    /// diffs the account map it replaces, so every account mutation path is covered).
    func noteProvisionalChanges<Row: Equatable>(
        _ table: WritableKeyPath<LoadJournal, LoadChanges>,
        from old: [String: Row],
        to new: [String: Row]
    ) {
        guard isLoadProvisional else { return }
        let changed = new.compactMap { id, row in old[id] == row ? nil : id }
        let deleted = old.keys.filter { new[$0] == nil }
        noteProvisionalChange(table, changed: changed, deleted: deleted)
    }

    /// Records a whole-array replacement (`updateSubcategories` and the link updates take
    /// the full new array) as the rows that differ.
    func noteProvisionalReplacement<Row: Equatable>(
        _ table: WritableKeyPath<LoadJournal, LoadChanges>,
        old: [Row],
        new: [Row],
        id: (Row) -> String
    ) {
        guard isLoadProvisional else { return }
        var oldById: [String: Row] = [:]
        oldById.reserveCapacity(old.count)
        for row in old { oldById[id(row)] = row }
        var changed: [String] = []
        var seen = Set<String>()
        for row in new {
            let rowId = id(row)
            seen.insert(rowId)
            if oldById[rowId] != row { changed.append(rowId) }
        }
        let deleted = oldById.keys.filter { !seen.contains($0) }
        noteProvisionalChange(table, changed: changed, deleted: deleted)
    }

    // MARK: - Held whole-table saves

    /// Whether a whole-table save of `table` may run now. When not, it is remembered and
    /// runs after the load (`runHeldWholeTableSaves`).
    func mayWriteWholeTable(_ table: WholeTable) -> Bool {
        guard holdsCompleteTable(table) else {
            heldWholeTableSaves.insert(table)
            return false
        }
        heldWholeTableSaves.remove(table)
        return true
    }

    /// Runs the whole-table saves held while memory was incomplete, for every table it now
    /// fully holds.
    func runHeldWholeTableSaves() {
        let held = heldWholeTableSaves
        if held.contains(.accounts) { persistAccountsToRepository() }
        if held.contains(.categories) { persistCategoriesToRepository() }
        if held.contains(.subcategories) { persistSubcategoriesToRepository() }
        if held.contains(.categorySubcategoryLinks) { persistCategorySubcategoryLinksToRepository() }
        if held.contains(.transactionSubcategoryLinks) { persistTransactionSubcategoryLinksToRepository() }
        if holdsCompleteTable(.recurring) { recurringStore.runHeldSaves() }
    }

    // MARK: - Merging

    /// The fetched rows of the small tables with memory's changes folded in. Transactions
    /// are merged off the main actor, inside `mergeAndBuildLoadSnapshot`.
    struct MergedLoadRows: Sendable {
        let accounts: [Account]
        let categories: [CustomCategory]
        let subcategories: [Subcategory]
        let categorySubcategoryLinks: [CategorySubcategoryLink]
        let transactionSubcategoryLinks: [TransactionSubcategoryLink]
        let transactionChanges: LoadChanges
        /// Current in-memory versions of `transactionChanges.changedIds`.
        let changedTransactions: [Transaction]
    }

    func mergeProvisionalChanges(
        accounts loadedAccounts: [Account],
        categories loadedCategories: [CustomCategory],
        subcategories loadedSubcategories: [Subcategory],
        categorySubcategoryLinks loadedCategoryLinks: [CategorySubcategoryLink],
        transactionSubcategoryLinks loadedTransactionLinks: [TransactionSubcategoryLink]
    ) -> MergedLoadRows {
        let journal = loadJournal
        return MergedLoadRows(
            accounts: journal.accounts.merge(
                into: loadedAccounts,
                changedRows: journal.accounts.changedIds.compactMap { accountById[$0] },
                id: \.id
            ),
            categories: journal.categories.merge(
                into: loadedCategories,
                changedRows: journal.categories.changedIds.compactMap { categoryById[$0] },
                id: \.id
            ),
            subcategories: journal.subcategories.merge(
                into: loadedSubcategories,
                changedRows: journal.subcategories.changedIds.compactMap { subcategoryById[$0] },
                id: \.id
            ),
            categorySubcategoryLinks: journal.categorySubcategoryLinks.merge(
                into: loadedCategoryLinks,
                changedRows: Self.rows(categorySubcategoryLinks, withIds: journal.categorySubcategoryLinks.changedIds, id: \.id),
                id: \.id
            ),
            transactionSubcategoryLinks: journal.transactionSubcategoryLinks.merge(
                into: loadedTransactionLinks,
                changedRows: Self.rows(transactionSubcategoryLinks, withIds: journal.transactionSubcategoryLinks.changedIds, id: \.id),
                id: \.id
            ),
            transactionChanges: journal.transactions,
            changedTransactions: journal.transactions.changedIds.compactMap { transactionById[$0] }
        )
    }

    /// The rows of `table` with the given ids, in the order of `ids`.
    private static func rows<Row>(_ table: [Row], withIds ids: [String], id: (Row) -> String) -> [Row] {
        guard !ids.isEmpty else { return [] }
        let wanted = Set(ids)
        var byId: [String: Row] = [:]
        for row in table where wanted.contains(id(row)) { byId[id(row)] = row }
        return ids.compactMap { byId[$0] }
    }

    /// Merges the transactions changed in memory into the fetched ones and builds the
    /// load snapshot from the result. Pure: runs off the main actor.
    nonisolated static func mergeAndBuildLoadSnapshot(
        loadedTransactions: [Transaction],
        transactionChanges: LoadChanges,
        changedTransactions: [Transaction],
        categories: [CustomCategory],
        subcategories: [Subcategory],
        categorySubcategoryLinks: [CategorySubcategoryLink],
        transactionSubcategoryLinks: [TransactionSubcategoryLink],
        baseCurrency: String,
        accountsCurrencyById: [String: String],
        needsColdStartCategoryAggregates: Bool,
        persistedCategoryAggregates: [CategoryAggregate] = [],
        needsColdStartAccountAggregates: Bool
    ) -> (transactions: [Transaction], snapshot: LoadedIndexSnapshot) {
        let transactions = transactionChanges.merge(
            into: loadedTransactions,
            changedRows: changedTransactions,
            id: \.id
        )
        let snapshot = buildLoadSnapshot(
            transactions: transactions,
            categories: categories,
            subcategories: subcategories,
            categorySubcategoryLinks: categorySubcategoryLinks,
            transactionSubcategoryLinks: transactionSubcategoryLinks,
            baseCurrency: baseCurrency,
            accountsCurrencyById: accountsCurrencyById,
            needsColdStartCategoryAggregates: needsColdStartCategoryAggregates,
            persistedCategoryAggregates: persistedCategoryAggregates,
            needsColdStartAccountAggregates: needsColdStartAccountAggregates
        )
        return (transactions, snapshot)
    }

    /// Closes a load: memory is complete, recorded changes are merged, held saves run and
    /// anyone waiting for the load resumes.
    func finishLoad() {
        hasCompletedInitialLoad = true
        hasLoadedAccountsAndCategories = true
        isLoadInFlight = false
        loadJournal = LoadJournal()
        recurringStore.clearRecordedChanges()
        runHeldWholeTableSaves()

        let waiters = loadWaiters
        loadWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
