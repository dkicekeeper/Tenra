//
//  TransactionStore+CategoryCRUD.swift
//  AIFinanceManager
//
//  Category and Subcategory CRUD operations extracted from TransactionStore.
//  Phase C: File split for maintainability.
//

import Foundation

// MARK: - Category CRUD Operations (Phase 3)

extension TransactionStore {

    /// Add a new category
    /// Phase 3: TransactionStore is now Single Source of Truth for categories
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

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
        }

    }

    /// Update an existing category
    /// Phase 3: TransactionStore is now Single Source of Truth for categories
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

        // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore

    }

    /// Delete a category
    /// Phase 3: TransactionStore is now Single Source of Truth for categories
    func deleteCategory(_ categoryId: String) {
        categories.removeAll { $0.id == categoryId }
        persistCategoriesToRepository()

        // ✅ Remove order from UserDefaults
        CategoryOrderManager.shared.removeOrder(for: categoryId)

        // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore

    }

    // MARK: - Subcategory CRUD Operations (Phase 10: CSV Import Fix)

    /// Add a new subcategory
    /// Phase 10: TransactionStore is now Single Source of Truth for subcategories
    func addSubcategory(_ subcategory: Subcategory) {
        subcategories.append(subcategory)

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategoriesToRepository()
        }

    }

    /// Update subcategories array (for bulk operations)
    /// Phase 10: Used by CategoriesViewModel during CSV import
    func updateSubcategories(_ newSubcategories: [Subcategory]) {
        subcategories = newSubcategories

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategoriesToRepository()
        }

    }

    /// Update category-subcategory links (for bulk operations)
    /// Phase 10: Used by CategoriesViewModel during CSV import
    func updateCategorySubcategoryLinks(_ newLinks: [CategorySubcategoryLink]) {
        categorySubcategoryLinks = newLinks

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistCategorySubcategoryLinksToRepository()
        }

    }

    /// Update transaction-subcategory links (for bulk operations)
    /// Phase 10: Used by CategoriesViewModel during CSV import
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
    /// ✨ Phase 10: Updated to just update in-memory array, persistence happens in finishImport()
    func syncCategories(_ newCategories: [CustomCategory]) async {

        categories = newCategories

        // ✨ Phase 10: Don't persist during import - will be done in finishImport()
        // This ensures all categories are saved synchronously at once
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
