//
//  CategoriesViewModel.swift
//  Tenra
//
//  Created on 2026
//
//  ViewModel for managing categories, subcategories, and category rules

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class CategoriesViewModel {
    // MARK: - Observable Properties

    /// Categories read directly from TransactionStore (Single Source of Truth)
    var customCategories: [CustomCategory] {
        transactionStore?.categories ?? []
    }

    var categoryRules: [CategoryRule] = []
    var subcategories: [Subcategory] = []
    var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []

    // MARK: - Private Properties

    @ObservationIgnored private let repository: DataRepositoryProtocol
    @ObservationIgnored private var currencyService: TransactionCurrencyService?
    @ObservationIgnored private var appSettings: AppSettings?

    /// @ObservationIgnored: set once at init, not reassigned; SwiftUI tracks categories
    /// directly on TransactionStore (same pattern as TransactionStore.coordinator)
    @ObservationIgnored weak var transactionStore: TransactionStore?

    // MARK: - Services (initialized eagerly for @Observable compatibility)

    /// CRUD service - handles category create/update/delete
    @ObservationIgnored private let crudService: CategoryCRUDServiceProtocol

    /// Subcategory coordinator - handles subcategory and link management
    @ObservationIgnored private let subcategoryCoordinator: CategorySubcategoryCoordinatorProtocol

    /// Budget coordinator
    @ObservationIgnored private let budgetCoordinator: CategoryBudgetCoordinatorProtocol

    /// Budget service for category budget management
    @ObservationIgnored private let budgetService: CategoryBudgetService

    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol = UserDefaultsRepository(),
        currencyService: TransactionCurrencyService? = nil,
        appSettings: AppSettings? = nil
    ) {
        self.repository = repository
        self.currencyService = currencyService
        self.appSettings = appSettings

        // Initialize services without delegates (required for @Observable compatibility)
        // Use delegate-less initializers, then set delegate after all properties are initialized
        self.crudService = CategoryCRUDService(repository: repository)
        self.subcategoryCoordinator = CategorySubcategoryCoordinator(repository: repository)
        self.budgetCoordinator = CategoryBudgetCoordinator(
            currencyService: currencyService,
            appSettings: appSettings
        )
        self.budgetService = CategoryBudgetService(
            currencyService: currencyService,
            appSettings: appSettings
        )

        self.categoryRules = repository.loadCategoryRules()
        self.subcategories = repository.loadSubcategories()
        self.categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        self.transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        // Set delegates after all properties are initialized
        if let service = self.crudService as? CategoryCRUDService {
            service.delegate = self
        }
        if let coordinator = self.subcategoryCoordinator as? CategorySubcategoryCoordinator {
            coordinator.delegate = self
        }
        if let coordinator = self.budgetCoordinator as? CategoryBudgetCoordinator {
            coordinator.delegate = self
        }
    }

    /// Sync subcategory data from TransactionStore on initial setup.
    /// Categories are a computed property; subcategory data still needs manual sync.
    func setupTransactionStoreObserver() {
        guard let transactionStore = transactionStore else { return }
        self.subcategories = transactionStore.subcategories
        self.categorySubcategoryLinks = transactionStore.categorySubcategoryLinks
        self.transactionSubcategoryLinks = transactionStore.transactionSubcategoryLinks
    }

    /// Sync subcategory data from TransactionStore.
    /// Categories are computed — only subcategory data needs manual sync.
    func syncCategoriesFromStore() {
        guard let transactionStore = transactionStore else { return }
        self.subcategories = transactionStore.subcategories
        self.categorySubcategoryLinks = transactionStore.categorySubcategoryLinks
        self.transactionSubcategoryLinks = transactionStore.transactionSubcategoryLinks
    }

    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        categoryRules = repository.loadCategoryRules()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()
    }

    // MARK: - Public Methods for Mutation

    /// Backward compatibility stub — categories are computed from TransactionStore.
    func updateCategories(_ categories: [CustomCategory]) {
    }

    // MARK: - Category CRUD Operations

    func addCategory(_ category: CustomCategory) {
        transactionStore?.addCategory(category)
    }

    func updateCategory(_ category: CustomCategory) {
        transactionStore?.updateCategory(category)
    }

    func deleteCategory(_ category: CustomCategory, deleteTransactions: Bool = false) {
        // deleteTransactions logic is handled by TransactionsViewModel
        transactionStore?.deleteCategory(category.id)
    }

    func deleteCategories(_ ids: Set<String>, deleteTransactions: Bool) async {
        let categoriesToDelete = customCategories.filter { ids.contains($0.id) }

        if deleteTransactions {
            for category in categoriesToDelete {
                await transactionStore?.deleteTransactions(forCategoryName: category.name, type: category.type)
            }
        }

        for category in categoriesToDelete {
            deleteCategory(category, deleteTransactions: deleteTransactions)
        }
    }

    // MARK: - Category Rules Operations

    func addRule(_ rule: CategoryRule) {
        // Проверяем, нет ли уже правила с таким описанием
        if !categoryRules.contains(where: { $0.description.lowercased() == rule.description.lowercased() }) {
            categoryRules.append(rule)
            repository.saveCategoryRules(categoryRules)
        }
    }

    func updateRule(_ rule: CategoryRule) {
        // CategoryRule не имеет id, поэтому ищем по description
        if let index = categoryRules.firstIndex(where: { $0.description.lowercased() == rule.description.lowercased() }) {
            var newRules = categoryRules
            newRules[index] = rule
            categoryRules = newRules
            repository.saveCategoryRules(categoryRules)
        }
    }

    func deleteRule(_ rule: CategoryRule) {
        categoryRules.removeAll { $0.description.lowercased() == rule.description.lowercased() }
        repository.saveCategoryRules(categoryRules)
    }

    // MARK: - Subcategory CRUD Operations

    func addSubcategory(name: String) -> Subcategory {
        return subcategoryCoordinator.addSubcategory(name: name)
    }

    func updateSubcategory(_ subcategory: Subcategory) {
        subcategoryCoordinator.updateSubcategory(subcategory)
    }

    func deleteSubcategory(_ subcategoryId: String) {
        subcategoryCoordinator.deleteSubcategory(subcategoryId)
    }

    func deleteSubcategories(_ ids: Set<String>) {
        for id in ids {
            deleteSubcategory(id)
        }
    }

    func searchSubcategories(query: String) -> [Subcategory] {
        return subcategoryCoordinator.searchSubcategories(query: query)
    }

    // MARK: - Category-Subcategory Links

    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String) {
        subcategoryCoordinator.linkSubcategoryToCategory(
            subcategoryId: subcategoryId,
            categoryId: categoryId
        )
    }

    func linkSubcategoryToCategoryWithoutSaving(subcategoryId: String, categoryId: String) {
        subcategoryCoordinator.linkSubcategoryToCategoryWithoutSaving(
            subcategoryId: subcategoryId,
            categoryId: categoryId
        )
    }

    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        subcategoryCoordinator.unlinkSubcategoryFromCategory(
            subcategoryId: subcategoryId,
            categoryId: categoryId
        )
    }

    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        return subcategoryCoordinator.getSubcategoriesForCategory(categoryId)
    }

    func reorderSubcategories(categoryId: String, orderedSubcategoryIds: [String]) {
        subcategoryCoordinator.reorderSubcategories(categoryId: categoryId, orderedSubcategoryIds: orderedSubcategoryIds)
    }

    // MARK: - Transaction-Subcategory Links

    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        return subcategoryCoordinator.getSubcategoriesForTransaction(transactionId)
    }

    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        subcategoryCoordinator.linkSubcategoriesToTransaction(
            transactionId: transactionId,
            subcategoryIds: subcategoryIds
        )
    }

    func linkSubcategoriesToTransactionWithoutSaving(transactionId: String, subcategoryIds: [String]) {
        subcategoryCoordinator.linkSubcategoriesToTransactionWithoutSaving(
            transactionId: transactionId,
            subcategoryIds: subcategoryIds
        )
    }

    func batchLinkSubcategoriesToTransaction(_ links: [String: [String]]) {
        subcategoryCoordinator.batchLinkSubcategoriesToTransaction(links)
    }

    func saveTransactionSubcategoryLinks() {
        subcategoryCoordinator.saveTransactionSubcategoryLinks()
    }

    // MARK: - Subcategory Statistics

    func subcategoryUsageCount(for subcategoryId: String) -> Int {
        transactionSubcategoryLinks.filter { $0.subcategoryId == subcategoryId }.count
    }

    func subcategoryLastUsedDate(for subcategoryId: String) -> Date? {
        let linkedTransactionIds = Set(
            transactionSubcategoryLinks
                .filter { $0.subcategoryId == subcategoryId }
                .map { $0.transactionId }
        )
        guard !linkedTransactionIds.isEmpty else { return nil }

        let latestDateString = transactionStore?.transactions
            .filter { linkedTransactionIds.contains($0.id) }
            .map { $0.date }
            .max()

        guard let dateString = latestDateString else { return nil }
        return DateFormatters.dateFormatter.date(from: dateString)
    }

    // MARK: - Batch Operations

    /// Сохраняет все данные CategoriesViewModel (используется после массового импорта)
    func saveAllData() {
        subcategoryCoordinator.saveAllData()
    }

    // MARK: - Budget Management

    func setBudget(
        for categoryId: String,
        amount: Double,
        period: CustomCategory.BudgetPeriod = .monthly,
        resetDay: Int = 1
    ) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryId }) else { return }

        var category = customCategories[index]
        category.budgetAmount = amount
        category.budgetPeriod = period
        category.budgetStartDate = Date()
        category.budgetResetDay = resetDay

        updateCategory(category)
    }

    func removeBudget(for categoryId: String) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryId }) else { return }

        var category = customCategories[index]
        category.budgetAmount = nil
        category.budgetStartDate = nil

        updateCategory(category)
    }

    func budgetProgress(for category: CustomCategory, transactions: [Transaction]) -> BudgetProgress? {
        return budgetService.budgetProgress(for: category, transactions: transactions)
    }

}

// MARK: - CategoryCRUDDelegate

extension CategoriesViewModel: CategoryCRUDDelegate {}

// MARK: - CategorySubcategoryDelegate

extension CategoriesViewModel: CategorySubcategoryDelegate {}

// MARK: - CategoryBudgetDelegate

extension CategoriesViewModel: CategoryBudgetDelegate {}
