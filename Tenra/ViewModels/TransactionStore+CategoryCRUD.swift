//
//  TransactionStore+CategoryCRUD.swift
//  Tenra
//
//  Category and Subcategory CRUD operations extracted from TransactionStore.
//

import Foundation

// MARK: - Category CRUD Operations

extension TransactionStore {

    /// Add a new category
    func addCategory(_ category: CustomCategory) {
        // Check if category already exists
        if categories.contains(where: { $0.id == category.id }) {
            return
        }

        // Assign order if not set
        var categoryToAdd = category
        if categoryToAdd.order == nil {
            // Get max order for this type
            let maxOrder = categories
                .filter { $0.type == category.type }
                .compactMap { $0.order }
                .max() ?? -1
            categoryToAdd.order = maxOrder + 1
        }

        categories.append(categoryToAdd)
        categoryById[categoryToAdd.id] = categoryToAdd
        categoryIdByName[categoryToAdd.name.lowercased()] = categoryToAdd.id
        categoriesMutationVersion &+= 1

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistCategoriesToRepository()

            // ✅ Save order to UserDefaults (UI preference)
            if let order = categoryToAdd.order {
                CategoryOrderManager.shared.setOrder(order, for: categoryToAdd.id)
            }

        }

    }

    /// Update an existing category
    func updateCategory(_ category: CustomCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else {
            return
        }

        let old = categories[index]
        categories[index] = category
        categoryById[category.id] = category

        // Move the name → id pointer if the user renamed the category. Aggregate
        // and per-name transaction buckets need to follow the new key, otherwise
        // CategoryBudgetService and CategoryDetailView would look up the old name
        // and miss everything. Done inline so the rename is atomic with the persist.
        if old.name != category.name {
            renameCategoryIndexKeys(from: old.name, to: category.name)
        }

        categoriesMutationVersion &+= 1
        persistCategoriesToRepository()

        // ✅ Save order to UserDefaults (UI preference, separate from CoreData)
        if let order = category.order {
            CategoryOrderManager.shared.setOrder(order, for: category.id)
        }

        // Selective style-cache invalidation — only when fields the cache reads
        // (icon/color/name/type) actually changed, and only for the affected
        // (name,type) pair. Pure budget edits no longer touch the cache at all;
        // renames move two keys (old + new); icon/color edits drop one key.
        let visualChanged = old.iconSource != category.iconSource
            || old.colorHex     != category.colorHex
            || old.name         != category.name
            || old.type         != category.type
        if visualChanged {
            CategoryStyleCache.shared.invalidate(name: old.name, type: old.type)
            if old.name != category.name || old.type != category.type {
                CategoryStyleCache.shared.invalidate(name: category.name, type: category.type)
            }
        }

    }

    /// Delete a category
    func deleteCategory(_ categoryId: String) {
        let removedName = categoryById[categoryId]?.name
        categories.removeAll { $0.id == categoryId }
        categoryById.removeValue(forKey: categoryId)
        if let name = removedName {
            categoryIdByName.removeValue(forKey: name.lowercased())
            dropAggregates(forCategoryName: name)
        }
        categoriesMutationVersion &+= 1
        persistCategoriesToRepository()

        // ✅ Remove order from UserDefaults
        CategoryOrderManager.shared.removeOrder(for: categoryId)

    }

    /// Atomically reorder categories. Sets `order` on each touched category to
    /// match its position in `orderedIds`, then performs a SINGLE persist —
    /// replaces the previous loop of `updateCategory` calls (which did one
    /// full CoreData save per moved category, i.e. O(N²) on a single drag).
    func reorderCategories(orderedIds: [String]) {
        var changed = false
        for (index, id) in orderedIds.enumerated() {
            guard let i = categories.firstIndex(where: { $0.id == id }) else { continue }
            if categories[i].order != index {
                categories[i].order = index
                categoryById[id] = categories[i]
                changed = true
                CategoryOrderManager.shared.setOrder(index, for: id)
            }
        }
        guard changed else { return }
        categoriesMutationVersion &+= 1
        persistCategoriesToRepository()
    }

    /// Delete multiple categories — single persist at the end
    func deleteCategories(_ ids: Set<String>) {
        let removedNames = ids.compactMap { categoryById[$0]?.name }
        categories.removeAll { ids.contains($0.id) }
        for id in ids { categoryById.removeValue(forKey: id) }
        for name in removedNames {
            categoryIdByName.removeValue(forKey: name.lowercased())
            dropAggregates(forCategoryName: name)
        }
        categoriesMutationVersion &+= 1
        persistCategoriesToRepository()

        for id in ids {
            CategoryOrderManager.shared.removeOrder(for: id)
        }
    }

    // MARK: - Subcategory CRUD Operations

    /// Add a new subcategory
    func addSubcategory(_ subcategory: Subcategory) {
        subcategories.append(subcategory)
        subcategoryById[subcategory.id] = subcategory
        subcategoriesMutationVersion &+= 1

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategoriesToRepository()
        }

    }

    /// Update subcategories array (for bulk operations)
    func updateSubcategories(_ newSubcategories: [Subcategory]) {
        subcategories = newSubcategories
        rebuildSubcategoryById()
        subcategoriesMutationVersion &+= 1

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategoriesToRepository()
        }

    }

    /// Update category-subcategory links (for bulk operations).
    /// Persists are debounced (300ms) so rapid edits collapse to one CoreData
    /// write instead of one-per-keystroke.
    func updateCategorySubcategoryLinks(_ newLinks: [CategorySubcategoryLink]) {
        categorySubcategoryLinks = newLinks
        rebuildSubcategoryIdsByCategoryId()
        subcategoriesMutationVersion &+= 1

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            scheduleCategorySubcategoryLinksPersist()
        }

    }

    /// Update transaction-subcategory links (for bulk operations).
    /// Debounced (300ms). Heavy hitter — the tx edit screen used to write the
    /// full link table on every check-mark toggle in the subcategory picker.
    func updateTransactionSubcategoryLinks(_ newLinks: [TransactionSubcategoryLink]) {
        transactionSubcategoryLinks = newLinks
        rebuildSubcategoryIdsByTransactionId()
        rebuildSubcategoryUsageStats()
        subcategoriesMutationVersion &+= 1

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            scheduleTransactionSubcategoryLinksPersist()
        }

    }

    // MARK: - Debounced Link Persistence

    /// 300ms debounce window for `categorySubcategoryLinks`. Reset on every
    /// new mutation; the last write wins.
    internal func scheduleCategorySubcategoryLinksPersist() {
        categorySubcategoryLinksPersistTask?.cancel()
        categorySubcategoryLinksPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.persistCategorySubcategoryLinksToRepository()
        }
    }

    internal func scheduleTransactionSubcategoryLinksPersist() {
        transactionSubcategoryLinksPersistTask?.cancel()
        transactionSubcategoryLinksPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.persistTransactionSubcategoryLinksToRepository()
        }
    }

    /// Synchronously flush any pending link persist tasks. Called from
    /// `finishImport()` so the bulk-import path doesn't lose pending writes.
    internal func flushSubcategoryLinkPersist() {
        categorySubcategoryLinksPersistTask?.cancel()
        transactionSubcategoryLinksPersistTask?.cancel()
        persistCategorySubcategoryLinksToRepository()
        persistTransactionSubcategoryLinksToRepository()
    }

    // MARK: - Category Synchronization

    /// Synchronize categories from CategoriesViewModel during CSV import
    /// This ensures TransactionStore knows about newly created categories
    /// before transactions are added
    func syncCategories(_ newCategories: [CustomCategory]) async {
        categories = newCategories
        rebuildCategoryLookups()
        categoriesMutationVersion &+= 1

        // Don't persist during import - will be done in finishImport()
        if !isImporting {
            // Only persist if not in import mode (e.g., manual sync)
            repository.saveCategories(newCategories)
        } else {
        }
    }

    // MARK: - Category & Subcategory Persistence

    internal func persistCategoriesToRepository() {
        repository.saveCategories(categories)
    }

    internal func persistSubcategoriesToRepository() {
        repository.saveSubcategories(subcategories)
    }

    internal func persistCategorySubcategoryLinksToRepository() {
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
    }

    internal func persistTransactionSubcategoryLinksToRepository() {
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
    }
}
