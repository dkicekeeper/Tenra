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

    /// Every `updateInitialBalancesSync` argument, in call order.
    var persistedInitialBalances: [[String: Double]] {
        lock.withLock { _persistedInitialBalances }
    }

    /// Every `renameTransactionsCategory` call, in call order.
    var categoryRenames: [(ids: [String], newName: String)] {
        lock.withLock { _categoryRenames }
    }

    // MARK: - Recorded

    func renameTransactionsCategory(ids: [String], to newName: String) {
        lock.withLock { _categoryRenames.append((ids, newName)) }
        inner.renameTransactionsCategory(ids: ids, to: newName)
    }

    func updateInitialBalancesSync(_ balances: [String: Double]) async {
        lock.withLock { _persistedInitialBalances.append(balances) }
        await inner.updateInitialBalancesSync(balances)
    }

    // MARK: - Transactions

    func loadTransactions(dateRange: DateInterval?) -> [Transaction] { inner.loadTransactions(dateRange: dateRange) }
    func saveTransactions(_ transactions: [Transaction]) { inner.saveTransactions(transactions) }
    func deleteTransactionImmediately(id: String) { inner.deleteTransactionImmediately(id: id) }
    func insertTransaction(_ transaction: Transaction) { inner.insertTransaction(transaction) }
    func updateTransactionFields(_ transaction: Transaction) { inner.updateTransactionFields(transaction) }
    func batchInsertTransactions(_ transactions: [Transaction]) { inner.batchInsertTransactions(transactions) }

    // MARK: - Accounts

    func loadAccounts() -> [Account] { inner.loadAccounts() }
    func saveAccounts(_ accounts: [Account]) { inner.saveAccounts(accounts) }
    func updateAccountBalance(accountId: String, balance: Double) { inner.updateAccountBalance(accountId: accountId, balance: balance) }
    func updateAccountBalances(_ balances: [String: Double]) { inner.updateAccountBalances(balances) }
    func updateAccountBalancesSync(_ balances: [String: Double]) async { await inner.updateAccountBalancesSync(balances) }

    // MARK: - Categories

    func loadCategories() -> [CustomCategory] { inner.loadCategories() }
    func saveCategories(_ categories: [CustomCategory]) { inner.saveCategories(categories) }

    // MARK: - Aggregates

    func loadAccountAggregates() -> [String: AccountAggregates] { inner.loadAccountAggregates() }
    func saveAccountAggregates(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) {
        inner.saveAccountAggregates(aggregates, currencyByAccountId: currencyByAccountId)
    }
    func saveAccountAggregatesSync(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) async {
        await inner.saveAccountAggregatesSync(aggregates, currencyByAccountId: currencyByAccountId)
    }
    func loadAggregates(year: Int16?, month: Int16?, limit: Int?) -> [CategoryAggregate] {
        inner.loadAggregates(year: year, month: month, limit: limit)
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
