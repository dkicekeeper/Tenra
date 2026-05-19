//
//  CategorySubcategoryCoordinator.swift
//  Tenra
//
//  Service for managing subcategories and their links to categories/transactions
//  Extracted from CategoriesViewModel for better separation of concerns
//

import Foundation

/// Service responsible for subcategory and link management
@MainActor
final class CategorySubcategoryCoordinator: CategorySubcategoryCoordinatorProtocol {

    // MARK: - Dependencies

    /// Delegate for callbacks to ViewModel
    weak var delegate: CategorySubcategoryDelegate?

    /// Repository for persistence
    private let repository: DataRepositoryProtocol

    // MARK: - Initialization

    /// Initialize with repository
    /// - Parameter repository: Data repository for persistence
    init(repository: DataRepositoryProtocol) {
        self.repository = repository
    }

    /// Convenience initializer with delegate
    /// - Parameters:
    ///   - delegate: Delegate for callbacks
    ///   - repository: Data repository for persistence
    init(delegate: CategorySubcategoryDelegate, repository: DataRepositoryProtocol) {
        self.delegate = delegate
        self.repository = repository
    }

    // MARK: - Subcategory CRUD

    func addSubcategory(name: String) -> Subcategory {
        guard let delegate = delegate else {
            return Subcategory(name: name)
        }

        let subcategory = Subcategory(name: name)
        delegate.subcategories.append(subcategory)

        if let transactionStore = delegate.transactionStore {
            transactionStore.addSubcategory(subcategory)
        } else {
            repository.saveSubcategories(delegate.subcategories)
        }

        return subcategory
    }

    func updateSubcategory(_ subcategory: Subcategory) {
        guard let delegate = delegate else {
            return
        }

        guard let index = delegate.subcategories.firstIndex(where: { $0.id == subcategory.id }) else {
            return
        }

        // Create new array to trigger @Published update
        var newSubcategories = delegate.subcategories
        newSubcategories[index] = subcategory

        delegate.subcategories = newSubcategories

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateSubcategories(newSubcategories)
        } else {
            repository.saveSubcategories(delegate.subcategories)
        }

    }

    func deleteSubcategory(_ subcategoryId: String) {
        guard let delegate = delegate else {
            return
        }

        // Remove all links to this subcategory
        delegate.categorySubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        delegate.transactionSubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }

        // Remove the subcategory itself
        delegate.subcategories.removeAll { $0.id == subcategoryId }

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateSubcategories(delegate.subcategories)
            transactionStore.updateCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
            transactionStore.updateTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        } else {
            repository.saveSubcategories(delegate.subcategories)
            repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
            repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        }

    }

    /// Delete multiple subcategories — all in-memory mutations first, single persist at the end
    func deleteSubcategories(_ ids: Set<String>) {
        guard let delegate = delegate else {
            return
        }

        // Remove all links and subcategories in bulk
        delegate.categorySubcategoryLinks.removeAll { ids.contains($0.subcategoryId) }
        delegate.transactionSubcategoryLinks.removeAll { ids.contains($0.subcategoryId) }
        delegate.subcategories.removeAll { ids.contains($0.id) }

        // Single persist for each data type
        if let transactionStore = delegate.transactionStore {
            transactionStore.updateSubcategories(delegate.subcategories)
            transactionStore.updateCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
            transactionStore.updateTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        } else {
            repository.saveSubcategories(delegate.subcategories)
            repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
            repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        }
    }

    func searchSubcategories(query: String) -> [Subcategory] {
        guard let delegate = delegate else { return [] }

        let queryLower = query.lowercased()
        return delegate.subcategories.filter { $0.name.lowercased().contains(queryLower) }
    }

    // MARK: - Category-Subcategory Links

    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String) {
        linkSubcategoryToCategoryWithoutSaving(subcategoryId: subcategoryId, categoryId: categoryId)

        guard let delegate = delegate else { return }

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        } else {
            repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        }

    }

    func linkSubcategoryToCategoryWithoutSaving(subcategoryId: String, categoryId: String) {
        guard let delegate = delegate else {
            return
        }

        // Check if link already exists
        let existingLink = delegate.categorySubcategoryLinks.first { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }

        guard existingLink == nil else {
            return
        }

        let link = CategorySubcategoryLink(categoryId: categoryId, subcategoryId: subcategoryId)
        delegate.categorySubcategoryLinks.append(link)
    }

    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        guard let delegate = delegate else {
            return
        }

        delegate.categorySubcategoryLinks.removeAll { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        } else {
            repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        }

    }

    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        guard let delegate = delegate else { return [] }
        // Fast path — pre-sorted ids from TransactionStore index.
        if let store = delegate.transactionStore,
           let orderedIds = store.subcategoryIdsByCategoryId[categoryId] {
            return orderedIds.compactMap { store.subcategoryById[$0] }
        }
        // Cold path (no store yet — happens only before setupTransactionStoreObserver runs).
        let links = delegate.categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .sorted { $0.sortOrder < $1.sortOrder }
        let orderedIds = links.map { $0.subcategoryId }
        let subcategoryMap = Dictionary(uniqueKeysWithValues: delegate.subcategories.map { ($0.id, $0) })
        return orderedIds.compactMap { subcategoryMap[$0] }
    }

    func reorderSubcategories(categoryId: String, orderedSubcategoryIds: [String]) {
        guard let delegate = delegate else { return }

        // Build a `(subcategoryId) → linkIndex` map for this category once,
        // then assign `sortOrder` in O(M) total instead of O(M × N_links).
        var indexBySubId: [String: Int] = [:]
        indexBySubId.reserveCapacity(orderedSubcategoryIds.count)
        for (i, link) in delegate.categorySubcategoryLinks.enumerated()
        where link.categoryId == categoryId {
            indexBySubId[link.subcategoryId] = i
        }

        for (newOrder, subId) in orderedSubcategoryIds.enumerated() {
            guard let linkIndex = indexBySubId[subId] else { continue }
            delegate.categorySubcategoryLinks[linkIndex].sortOrder = newOrder
        }

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        } else {
            repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        }
    }

    // MARK: - Transaction-Subcategory Links

    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        guard let delegate = delegate else { return [] }
        // Fast path — pre-built id list from the maintained index. O(M) where M ≤ ~5.
        if let store = delegate.transactionStore,
           let ids = store.subcategoryIdsByTransactionId[transactionId] {
            return ids.compactMap { store.subcategoryById[$0] }
        }
        // Cold path.
        let linkedSubcategoryIds = delegate.transactionSubcategoryLinks
            .filter { $0.transactionId == transactionId }
            .map { $0.subcategoryId }
        return delegate.subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }

    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        guard let delegate = delegate else {
            return
        }

        // Remove old links
        delegate.transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }

        // Add new links
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            delegate.transactionSubcategoryLinks.append(link)
        }

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        } else {
            repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        }

    }

    func linkSubcategoriesToTransactionWithoutSaving(transactionId: String, subcategoryIds: [String]) {
        guard let delegate = delegate else {
            return
        }

        // Remove old links
        delegate.transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }

        // Add new links
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            delegate.transactionSubcategoryLinks.append(link)
        }
        // Do not save - will be saved in batch
    }

    func batchLinkSubcategoriesToTransaction(_ links: [String: [String]]) {
        guard let delegate = delegate else {
            return
        }

        // Remove old links for all transactions in batch
        let transactionIds = Set(links.keys)
        delegate.transactionSubcategoryLinks.removeAll { transactionIds.contains($0.transactionId) }

        // Add new links
        for (transactionId, subcategoryIds) in links {
            for subcategoryId in subcategoryIds {
                let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
                delegate.transactionSubcategoryLinks.append(link)
            }
        }

        if let transactionStore = delegate.transactionStore {
            transactionStore.updateTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        } else {
            repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)
        }

    }

    // MARK: - Batch Operations

    func saveTransactionSubcategoryLinks() {
        guard let delegate = delegate else {
            return
        }

        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

    }

    func saveAllData() {
        guard let delegate = delegate else {
            return
        }

        repository.saveSubcategories(delegate.subcategories)
        repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

    }
}

// MARK: - Factory Methods

extension CategorySubcategoryCoordinator {
    /// Create coordinator with delegate
    /// - Parameters:
    ///   - delegate: Delegate for callbacks
    ///   - repository: Data repository
    /// - Returns: Configured coordinator
    static func create(
        delegate: CategorySubcategoryDelegate,
        repository: DataRepositoryProtocol
    ) -> CategorySubcategoryCoordinator {
        CategorySubcategoryCoordinator(delegate: delegate, repository: repository)
    }
}
