//
//  RecordingDataRepository.swift
//  TenraTests
//
//  A DataRepositoryProtocol that forwards everything to an isolated
//  UserDefaultsRepository and records the calls tests need to observe.
//  UserDefaultsRepository implements the CoreData-only persist paths as no-ops
//  (e.g. updateInitialBalancesSync), so a test that must prove "this was
//  persisted" needs to see the call itself.
//

import Foundation
@testable import Tenra

final class RecordingDataRepository: DataRepositoryProtocol, @unchecked Sendable {

    private let inner = UserDefaultsRepository(
        userDefaults: UserDefaults(suiteName: "tests.recording.\(UUID().uuidString)")!
    )
    private let lock = NSLock()
    private var _persistedInitialBalances: [[String: Double]] = []
    private var _categoryRenames: [(ids: [String], newName: String)] = []
    private var _balanceWrites: [[String: Double]] = []
    private var balanceWriteCalls = 0
    private var _savedAccountSnapshots: [[Account]] = []

    /// Optional delay before an `updateAccountBalancesSync` call finishes, by call index
    /// (0-based). Lets a test make concurrent writes finish out of order, as slow CoreData
    /// saves can. Set it before the first write.
    var balanceWriteDelay: (@Sendable (Int) -> Duration)?

    /// When set, `loadTransactions` waits on it before returning: a test can act while
    /// `TransactionStore.loadData` is in flight. Set it before the load starts.
    var loadTransactionsGate: LoadGate?

    /// What `loadAggregates` / `loadAccountAggregates` return (the inner repository keeps
    /// none): a warm-start table persisted before launch. Set before the load starts.
    var persistedCategoryAggregates: [CategoryAggregate] = []
    var persistedAccountAggregates: [String: AccountAggregates] = [:]

    private var _bulkDeletes: [[String]] = []
    private var _bulkUpdates: [[String]] = []
    private var _rowDeletes: [String] = []
    private var _rowUpdates: [String] = []

    /// Every `updateInitialBalancesSync` argument, in call order.
    var persistedInitialBalances: [[String: Double]] {
        lock.withLock { _persistedInitialBalances }
    }

    /// Every `renameTransactionsCategory` call, in call order.
    var categoryRenames: [(ids: [String], newName: String)] {
        lock.withLock { _categoryRenames }
    }

    /// Every `updateAccountBalancesSync` argument, in the order the writes FINISHED.
    var balanceWrites: [[String: Double]] {
        lock.withLock { _balanceWrites }
    }

    /// Every `saveAccounts` argument, in call order.
    var savedAccountSnapshots: [[Account]] {
        lock.withLock { _savedAccountSnapshots }
    }

    /// Ids of every `deleteTransactions(ids:)` call, in call order.
    var bulkDeletes: [[String]] { lock.withLock { _bulkDeletes } }
    /// Ids of every `updateTransactionsFields` call, in call order.
    var bulkUpdates: [[String]] { lock.withLock { _bulkUpdates } }
    /// Every per-row `deleteTransactionImmediately` id.
    var rowDeletes: [String] { lock.withLock { _rowDeletes } }
    /// Every per-row `updateTransactionFields` id.
    var rowUpdates: [String] { lock.withLock { _rowUpdates } }

    // MARK: - Recorded

    func deleteTransactions(ids: [String]) async {
        lock.withLock { _bulkDeletes.append(ids) }
        await inner.deleteTransactions(ids: ids)
    }

    func updateTransactionsFields(_ transactions: [Transaction]) async {
        lock.withLock { _bulkUpdates.append(transactions.map(\.id)) }
        await inner.updateTransactionsFields(transactions)
    }

    func renameTransactionsCategory(ids: [String], to newName: String) {
        lock.withLock { _categoryRenames.append((ids, newName)) }
        inner.renameTransactionsCategory(ids: ids, to: newName)
    }

    func updateInitialBalancesSync(_ balances: [String: Double]) async {
        lock.withLock { _persistedInitialBalances.append(balances) }
        await inner.updateInitialBalancesSync(balances)
    }

    // MARK: - Transactions

    func loadTransactions(dateRange: DateInterval?) -> [Transaction] {
        let rows = inner.loadTransactions(dateRange: dateRange)
        loadTransactionsGate?.wait()
        return rows
    }
    func saveTransactions(_ transactions: [Transaction]) { inner.saveTransactions(transactions) }
    func deleteTransactionImmediately(id: String) {
        lock.withLock { _rowDeletes.append(id) }
        inner.deleteTransactionImmediately(id: id)
    }
    func insertTransaction(_ transaction: Transaction) { inner.insertTransaction(transaction) }
    func updateTransactionFields(_ transaction: Transaction) {
        lock.withLock { _rowUpdates.append(transaction.id) }
        inner.updateTransactionFields(transaction)
    }
    func batchInsertTransactions(_ transactions: [Transaction]) { inner.batchInsertTransactions(transactions) }

    // MARK: - Accounts

    func loadAccounts() -> [Account] { inner.loadAccounts() }
    func saveAccounts(_ accounts: [Account]) {
        lock.withLock { _savedAccountSnapshots.append(accounts) }
        inner.saveAccounts(accounts)
    }
    func updateAccountBalance(accountId: String, balance: Double) { inner.updateAccountBalance(accountId: accountId, balance: balance) }
    func updateAccountBalances(_ balances: [String: Double]) { inner.updateAccountBalances(balances) }
    func updateAccountBalancesSync(_ balances: [String: Double]) async {
        let index: Int = lock.withLock {
            defer { balanceWriteCalls += 1 }
            return balanceWriteCalls
        }
        if let delay = balanceWriteDelay?(index) {
            try? await Task.sleep(for: delay)
        }
        lock.withLock { _balanceWrites.append(balances) }
        await inner.updateAccountBalancesSync(balances)
    }

    // MARK: - Categories

    func loadCategories() -> [CustomCategory] { inner.loadCategories() }
    func saveCategories(_ categories: [CustomCategory]) { inner.saveCategories(categories) }

    // MARK: - Aggregates

    func loadAccountAggregates() -> [String: AccountAggregates] { persistedAccountAggregates }
    func saveAccountAggregates(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) {
        inner.saveAccountAggregates(aggregates, currencyByAccountId: currencyByAccountId)
    }
    func saveAccountAggregatesSync(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) async {
        await inner.saveAccountAggregatesSync(aggregates, currencyByAccountId: currencyByAccountId)
    }
    func loadAggregates(year: Int16?, month: Int16?, limit: Int?) -> [CategoryAggregate] {
        persistedCategoryAggregates
    }
    func saveAggregates(_ aggregates: [CategoryAggregate]) { inner.saveAggregates(aggregates) }

    // MARK: - Rules, recurring, subcategories

    func loadCategoryRules() -> [CategoryRule] { inner.loadCategoryRules() }
    func saveCategoryRules(_ rules: [CategoryRule]) { inner.saveCategoryRules(rules) }
    func loadRecurringSeries() -> [RecurringSeries] { inner.loadRecurringSeries() }
    func saveRecurringSeries(_ series: [RecurringSeries]) { inner.saveRecurringSeries(series) }
    func loadRecurringOccurrences() -> [RecurringOccurrence] { inner.loadRecurringOccurrences() }
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) { inner.saveRecurringOccurrences(occurrences) }
    func loadSubcategories() -> [Subcategory] { inner.loadSubcategories() }
    func saveSubcategories(_ subcategories: [Subcategory]) { inner.saveSubcategories(subcategories) }
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] { inner.loadCategorySubcategoryLinks() }
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) { inner.saveCategorySubcategoryLinks(links) }
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] { inner.loadTransactionSubcategoryLinks() }
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) { inner.saveTransactionSubcategoryLinks(links) }
    func clearAllData() { inner.clearAllData() }
}

/// Holds background calls until the test opens it; once open, it stays open.
final class LoadGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false
    private var waiting = false

    /// Blocks the calling (background) thread until `open()`, or 10 s at most.
    func wait() {
        condition.lock()
        defer { condition.unlock() }
        waiting = true
        let deadline = Date().addingTimeInterval(10)
        while !isOpen {
            if !condition.wait(until: deadline) { break }
        }
    }

    /// True once a caller has been held.
    var isWaiting: Bool {
        condition.lock()
        defer { condition.unlock() }
        return waiting
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}
