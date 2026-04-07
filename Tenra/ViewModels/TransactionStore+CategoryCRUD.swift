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

        categories[index] = category
        persistCategoriesToRepository()

        // ✅ Save order to UserDefaults (UI preference, separate from CoreData)
        if let order = category.order {
            CategoryOrderManager.shared.setOrder(order, for: category.id)
        }

        // ✅ FIX: Invalidate style cache so icon/color changes reflect immediately.
        // CategoryDisplayDataMapper reads icon data through CategoryStyleCache.
        // Without this, the singleton cache may serve stale icon data until next restart.
        CategoryStyleCache.shared.invalidateCache()

    }

    /// Delete a category
    func deleteCategory(_ categoryId: String) {
        categories.removeAll { $0.id == categoryId }
        persistCategoriesToRepository()

        // ✅ Remove order from UserDefaults
        CategoryOrderManager.shared.removeOrder(for: categoryId)

    }

    /// Delete multiple categories — single persist at the end
    func deleteCategories(_ ids: Set<String>) {
        categories.removeAll { ids.contains($0.id) }
        persistCategoriesToRepository()

        for id in ids {
            CategoryOrderManager.shared.removeOrder(for: id)
        }
    }

    // MARK: - Subcategory CRUD Operations

    /// Add a new subcategory
    func addSubcategory(_ subcategory: Subcategory) {
        subcategories.append(subcategory)

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategoriesToRepository()
        }

    }

    /// Update subcategories array (for bulk operations)
    func updateSubcategories(_ newSubcategories: [Subcategory]) {
        subcategories = newSubcategories

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategoriesToRepository()
        }

    }

    /// Update category-subcategory links (for bulk operations)
    func updateCategorySubcategoryLinks(_ newLinks: [CategorySubcategoryLink]) {
        categorySubcategoryLinks = newLinks

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistCategorySubcategoryLinksToRepository()
        }

    }

    /// Update transaction-subcategory links (for bulk operations)
    func updateTransactionSubcategoryLinks(_ newLinks: [TransactionSubcategoryLink]) {
        transactionSubcategoryLinks = newLinks

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistTransactionSubcategoryLinksToRepository()
        }

    }

    // MARK: - Category Synchronization

    /// Synchronize categories from CategoriesViewModel during CSV import
    /// This ensures TransactionStore knows about newly created categories
    /// before transactions are added
    func syncCategories(_ newCategories: [CustomCategory]) async {
        categories = newCategories

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
