//
//  CategoryCRUDServiceProtocol.swift
//  AIFinanceManager
//
//  Protocol for category CRUD operations
//  Extracted from CategoriesViewModel for better separation of concerns
//

import Foundation

/// Protocol defining category CRUD operations
@MainActor
protocol CategoryCRUDServiceProtocol {
    /// Add a new category
    /// - Parameter category: The category to add
    func addCategory(_ category: CustomCategory)

    /// Update an existing category
    /// - Parameter category: The category to update
    func updateCategory(_ category: CustomCategory)

    /// Delete a category
    /// - Parameter category: The category to delete
    func deleteCategory(_ category: CustomCategory)
}

/// Delegate protocol for CategoryCRUDService callbacks
@MainActor
protocol CategoryCRUDDelegate: AnyObject {
    /// The current list of custom categories (read-only)
    var customCategories: [CustomCategory] { get }

    /// Update categories array (controlled mutation)
    /// - Parameter categories: New categories array
    func updateCategories(_ categories: [CustomCategory])
}
