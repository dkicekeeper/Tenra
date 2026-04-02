//
//  EntityMappingServiceProtocol.swift
//  AIFinanceManager
//
//  Simplified CSV Import Architecture - Phase 11
//  Removed ViewModels dependencies - works with TransactionStore only
//

import Foundation

/// Protocol for entity (account, category, subcategory) resolution during CSV import
/// Works directly with TransactionStore (Single Source of Truth)
/// ViewModels update automatically via Combine subscriptions
@MainActor
protocol EntityMappingServiceProtocol {
    /// Resolves an account by name, checking cache, mapping, and TransactionStore
    /// Creates a new account if needed directly in TransactionStore
    /// - Parameters:
    ///   - name: Account name from CSV
    ///   - currency: Account currency
    ///   - mapping: Entity mapping configuration
    /// - Returns: Resolution result indicating if account was found or created
    func resolveAccount(
        name: String,
        currency: String,
        mapping: EntityMapping
    ) async -> AccountResolutionResult

    /// Resolves a category by name, checking cache, mapping, and TransactionStore
    /// Creates a new category if needed directly in TransactionStore
    /// - Parameters:
    ///   - name: Category name from CSV
    ///   - type: Transaction type for category
    ///   - mapping: Entity mapping configuration
    /// - Returns: Resolution result indicating if category was found or created
    func resolveCategory(
        name: String,
        type: TransactionType,
        mapping: EntityMapping
    ) async -> CategoryResolutionResult

    /// Resolves multiple subcategories, checking cache and TransactionStore
    /// Creates new subcategories if needed and links them to the category
    /// - Parameters:
    ///   - names: Array of subcategory names from CSV
    ///   - categoryId: Parent category ID for linking
    /// - Returns: Array of resolution results for each subcategory
    func resolveSubcategories(
        names: [String],
        categoryId: String
    ) async -> [SubcategoryResolutionResult]

    /// Converts a validated CSV row + resolved entity IDs into a Transaction value.
    /// Previously `TransactionConverterService.convertRow()` — merged into this protocol (Phase 37).
    func convertRow(
        _ csvRow: CSVRow,
        accountId: String?,
        targetAccountId: String?,
        categoryName: String,
        categoryId: String,
        subcategoryIds: [String],
        rowIndex: Int
    ) -> Transaction
}

// MARK: - Resolution Result Types

/// Result of account resolution operation
enum AccountResolutionResult {
    /// Account already exists, returns ID
    case existing(id: String)
    /// Account was created, returns new ID
    case created(id: String)
    /// Account resolution was skipped (reserved name or empty)
    case skipped
}

/// Result of category resolution operation
enum CategoryResolutionResult {
    /// Category already exists, returns ID and name
    case existing(id: String, name: String)
    /// Category was created, returns new ID and name
    case created(id: String, name: String)
}

/// Result of subcategory resolution operation
enum SubcategoryResolutionResult {
    /// Subcategory already exists, returns ID
    case existing(id: String)
    /// Subcategory was created, returns new ID
    case created(id: String)
}
