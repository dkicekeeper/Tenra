//
//  CoreDataRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Core Data implementation of DataRepositoryProtocol
//  Acts as a facade that delegates to specialized domain repositories

import Foundation
import CoreData
import os

/// Core Data implementation of DataRepositoryProtocol
/// Delegates operations to specialized repositories for better separation of concerns
nonisolated final class CoreDataRepository: DataRepositoryProtocol {

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CoreDataRepository")

    // MARK: - Properties

    private let stack: CoreDataStack
    private let saveCoordinator: CoreDataSaveCoordinator

    // Specialized repositories — `let` (not `lazy var`) for thread-safety: lazy var is not
    // thread-safe in Swift and would violate Sendable requirements when called from Task.detached.
    private let transactionRepository: TransactionRepositoryProtocol
    private let accountRepository: AccountRepositoryProtocol
    private let categoryRepository: CategoryRepositoryProtocol
    private let recurringRepository: RecurringRepositoryProtocol

    // MARK: - Initialization

    init() {
        let stack = CoreDataStack.shared
        let saveCoordinator = CoreDataSaveCoordinator()
        self.stack = stack
        self.saveCoordinator = saveCoordinator
        self.transactionRepository = TransactionRepository(stack: stack, saveCoordinator: saveCoordinator)
        self.accountRepository = AccountRepository(stack: stack, saveCoordinator: saveCoordinator)
        self.categoryRepository = CategoryRepository(stack: stack, saveCoordinator: saveCoordinator)
        self.recurringRepository = RecurringRepository(stack: stack, saveCoordinator: saveCoordinator)
    }

    // MARK: - Transactions (Delegated to TransactionRepository)

    func loadTransactions(dateRange: DateInterval? = nil) -> [Transaction] {
        return transactionRepository.loadTransactions(dateRange: dateRange)
    }

    func saveTransactions(_ transactions: [Transaction]) {
        transactionRepository.saveTransactions(transactions)
    }

    /// Синхронно сохранить транзакции в Core Data (для импорта CSV)
    func saveTransactionsSync(_ transactions: [Transaction]) throws {
        try transactionRepository.saveTransactionsSync(transactions)
    }

    func deleteTransactionImmediately(id: String) {
        transactionRepository.deleteTransactionImmediately(id: id)
    }

    func insertTransaction(_ transaction: Transaction) {
        transactionRepository.insertTransaction(transaction)
    }

    func updateTransactionFields(_ transaction: Transaction) {
        transactionRepository.updateTransactionFields(transaction)
    }

    func batchInsertTransactions(_ transactions: [Transaction]) {
        transactionRepository.batchInsertTransactions(transactions)
    }

    // MARK: - Accounts (Delegated to AccountRepository)

    func loadAccounts() -> [Account] {
        return accountRepository.loadAccounts()
    }

    func saveAccounts(_ accounts: [Account]) {
        accountRepository.saveAccounts(accounts)
    }

    /// Синхронно сохранить счета в Core Data (для импорта CSV)
    func saveAccountsSync(_ accounts: [Account]) throws {
        try accountRepository.saveAccountsSync(accounts)
    }

    /// Обновить баланс счёта в Core Data
    func updateAccountBalance(accountId: String, balance: Double) {
        accountRepository.updateAccountBalance(accountId: accountId, balance: balance)
    }

    /// Batch-обновление балансов нескольких счетов (fire-and-forget)
    func updateAccountBalances(_ balances: [String: Double]) {
        accountRepository.updateAccountBalances(balances)
    }

    /// Batch-обновление балансов нескольких счетов — awaited, гарантированно завершается
    func updateAccountBalancesSync(_ balances: [String: Double]) async {
        await accountRepository.updateAccountBalancesSync(balances)
    }

    /// Load all persisted account balances from Core Data
    func loadAllAccountBalances() -> [String: Double] {
        return accountRepository.loadAllAccountBalances()
    }

    // MARK: - Categories (Delegated to CategoryRepository)

    func loadCategories() -> [CustomCategory] {
        return categoryRepository.loadCategories()
    }

    func saveCategories(_ categories: [CustomCategory]) {
        categoryRepository.saveCategories(categories)
    }

    /// Синхронно сохранить категории в Core Data (для импорта CSV)
    func saveCategoriesSync(_ categories: [CustomCategory]) throws {
        try categoryRepository.saveCategoriesSync(categories)
    }

    // MARK: - Category Rules (Delegated to CategoryRepository)

    func loadCategoryRules() -> [CategoryRule] {
        return categoryRepository.loadCategoryRules()
    }

    func saveCategoryRules(_ rules: [CategoryRule]) {
        categoryRepository.saveCategoryRules(rules)
    }

    // MARK: - Recurring Series (Delegated to RecurringRepository)

    func loadRecurringSeries() -> [RecurringSeries] {
        return recurringRepository.loadRecurringSeries()
    }

    func saveRecurringSeries(_ series: [RecurringSeries]) {
        recurringRepository.saveRecurringSeries(series)
    }

    // MARK: - Recurring Occurrences (Delegated to RecurringRepository)

    func loadRecurringOccurrences() -> [RecurringOccurrence] {
        return recurringRepository.loadRecurringOccurrences()
    }

    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {
        recurringRepository.saveRecurringOccurrences(occurrences)
    }

    // MARK: - Subcategories (Delegated to CategoryRepository)

    func loadSubcategories() -> [Subcategory] {
        return categoryRepository.loadSubcategories()
    }

    func saveSubcategories(_ subcategories: [Subcategory]) {
        categoryRepository.saveSubcategories(subcategories)
    }

    /// Синхронно сохранить подкатегории в Core Data (для импорта CSV)
    func saveSubcategoriesSync(_ subcategories: [Subcategory]) throws {
        try categoryRepository.saveSubcategoriesSync(subcategories)
    }

    // MARK: - Category-Subcategory Links (Delegated to CategoryRepository)

    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        return categoryRepository.loadCategorySubcategoryLinks()
    }

    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {
        categoryRepository.saveCategorySubcategoryLinks(links)
    }

    /// Синхронно сохранить связи категория-подкатегория в Core Data (для импорта CSV)
    func saveCategorySubcategoryLinksSync(_ links: [CategorySubcategoryLink]) throws {
        try categoryRepository.saveCategorySubcategoryLinksSync(links)
    }

    // MARK: - Transaction-Subcategory Links (Delegated to CategoryRepository)

    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        return categoryRepository.loadTransactionSubcategoryLinks()
    }

    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {
        categoryRepository.saveTransactionSubcategoryLinks(links)
    }

    /// Синхронно сохранить связи транзакция-подкатегория в Core Data (для импорта CSV)
    func saveTransactionSubcategoryLinksSync(_ links: [TransactionSubcategoryLink]) throws {
        try categoryRepository.saveTransactionSubcategoryLinksSync(links)
    }

    // MARK: - Category Aggregates (Delegated to CategoryRepository)

    /// Load aggregates with optional filtering for performance
    func loadAggregates(
        year: Int16? = nil,
        month: Int16? = nil,
        limit: Int? = nil
    ) -> [CategoryAggregate] {
        return categoryRepository.loadAggregates(year: year, month: month, limit: limit)
    }

    /// Сохранить агрегаты категорий в Core Data
    func saveAggregates(_ aggregates: [CategoryAggregate]) {
        categoryRepository.saveAggregates(aggregates)
    }

    // MARK: - Clear All Data

    func clearAllData() {
        do {
            try stack.resetAllData()
            UserDefaultsRepository().clearAllData()
        } catch {
            Self.logger.error("clearAllData: CoreData resetAllData failed — UserDefaults may be out of sync: \(error.localizedDescription, privacy: .public)")
        }
    }
}
