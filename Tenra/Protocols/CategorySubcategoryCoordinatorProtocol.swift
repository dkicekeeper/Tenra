//
//  CategorySubcategoryCoordinatorProtocol.swift
//  Tenra
//
//  Protocol for managing category-subcategory and transaction-subcategory links
//  Extracted from CategoriesViewModel for better separation of concerns
//

import Foundation

/// Protocol defining subcategory management operations
@MainActor
protocol CategorySubcategoryCoordinatorProtocol {
    // MARK: - Subcategory CRUD

    /// Add a new subcategory
    /// - Parameter name: Subcategory name
    /// - Returns: The created subcategory
    func addSubcategory(name: String) -> Subcategory

    /// Update an existing subcategory
    /// - Parameter subcategory: The subcategory to update
    func updateSubcategory(_ subcategory: Subcategory)

    /// Delete a subcategory and all its links
    /// - Parameter subcategoryId: ID of the subcategory to delete
    func deleteSubcategory(_ subcategoryId: String)

    /// Delete multiple subcategories — batch operation with single persist
    /// - Parameter ids: Set of subcategory IDs to delete
    func deleteSubcategories(_ ids: Set<String>)

    /// Search subcategories by query
    /// - Parameter query: Search query
    /// - Returns: Matching subcategories
    func searchSubcategories(query: String) -> [Subcategory]

    // MARK: - Category-Subcategory Links

    /// Link a subcategory to a category
    /// - Parameters:
    ///   - subcategoryId: Subcategory ID
    ///   - categoryId: Category ID
    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String)

    /// Link a subcategory to a category without immediate save (for batch operations)
    /// - Parameters:
    ///   - subcategoryId: Subcategory ID
    ///   - categoryId: Category ID
    func linkSubcategoryToCategoryWithoutSaving(subcategoryId: String, categoryId: String)

    /// Unlink a subcategory from a category
    /// - Parameters:
    ///   - subcategoryId: Subcategory ID
    ///   - categoryId: Category ID
    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String)

    /// Get all subcategories linked to a category
    /// - Parameter categoryId: Category ID
    /// - Returns: Array of linked subcategories sorted by sortOrder
    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory]

    /// Reorder subcategories within a category
    /// - Parameters:
    ///   - categoryId: Category ID
    ///   - orderedSubcategoryIds: Subcategory IDs in desired order
    func reorderSubcategories(categoryId: String, orderedSubcategoryIds: [String])

    // MARK: - Transaction-Subcategory Links

    /// Get all subcategories linked to a transaction
    /// - Parameter transactionId: Transaction ID
    /// - Returns: Array of linked subcategories
    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory]

    /// Link subcategories to a transaction
    /// - Parameters:
    ///   - transactionId: Transaction ID
    ///   - subcategoryIds: Array of subcategory IDs
    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String])

    /// Link subcategories to a transaction without immediate save (for batch operations)
    /// - Parameters:
    ///   - transactionId: Transaction ID
    ///   - subcategoryIds: Array of subcategory IDs
    func linkSubcategoriesToTransactionWithoutSaving(transactionId: String, subcategoryIds: [String])

    /// Batch link subcategories to multiple transactions
    /// - Parameter links: Dictionary mapping transaction IDs to subcategory ID arrays
    func batchLinkSubcategoriesToTransaction(_ links: [String: [String]])

    // MARK: - Batch Operations

    /// Save transaction-subcategory links (after batch operations)
    func saveTransactionSubcategoryLinks()

    /// Save all subcategory data (after batch operations)
    func saveAllData()
}

/// Delegate protocol for CategorySubcategoryCoordinator callbacks
@MainActor
protocol CategorySubcategoryDelegate: AnyObject {
    /// Current list of subcategories
    var subcategories: [Subcategory] { get set }

    /// Current category-subcategory links
    var categorySubcategoryLinks: [CategorySubcategoryLink] { get set }

    /// Current transaction-subcategory links
    var transactionSubcategoryLinks: [TransactionSubcategoryLink] { get set }

    var transactionStore: TransactionStore? { get }
}
