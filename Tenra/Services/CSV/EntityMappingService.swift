//
//  EntityMappingService.swift
//  AIFinanceManager
//
//  Simplified CSV Import Architecture - Phase 11
//  Works ONLY with TransactionStore (Single Source of Truth)
//  Removed ViewModels dependencies - they update automatically via Combine
//

import Foundation
import SwiftUI

/// Simplified service for resolving entities during CSV import
/// Works directly with TransactionStore - ViewModels update automatically via Combine subscriptions
@MainActor
class EntityMappingService: EntityMappingServiceProtocol {

    // MARK: - Properties

    private let cache: ImportCacheManager
    private let transactionStore: TransactionStore

    // MARK: - Initialization

    init(cache: ImportCacheManager, transactionStore: TransactionStore) {
        self.cache = cache
        self.transactionStore = transactionStore
    }

    // MARK: - Account Resolution

    func resolveAccount(
        name: String,
        currency: String,
        mapping: EntityMapping
    ) async -> AccountResolutionResult {

        // Reserved names (never create accounts with these names)
        let reservedNames = [
            String(localized: "category.other").lowercased(),
            "other",
            "другое"
        ]

        let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased()

        guard !normalizedName.isEmpty,
              !reservedNames.contains(normalizedName) else {
            return .skipped
        }

        // Check mapping first
        if let mappedId = mapping.accountMappings[name] {
            cache.cacheAccount(name: name, id: mappedId)
            return .existing(id: mappedId)
        }

        // Check cache
        if let cachedId = cache.getAccount(name: name) {
            return .existing(id: cachedId)
        }

        // Check TransactionStore (Single Source of Truth)
        if let account = transactionStore.accounts.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName
        }) {
            cache.cacheAccount(name: name, id: account.id)
            return .existing(id: account.id)
        }

        // Create new account directly in TransactionStore
        let newAccount = Account(
            name: name,
            currency: currency,
            iconSource: nil,
            shouldCalculateFromTransactions: true,  // CSV imports always calculate from transactions
            initialBalance: 0.0
        )

        transactionStore.addAccount(newAccount)
        cache.cacheAccount(name: name, id: newAccount.id)


        return .created(id: newAccount.id)
    }

    // MARK: - Category Resolution

    func resolveCategory(
        name: String,
        type: TransactionType,
        mapping: EntityMapping
    ) async -> CategoryResolutionResult {

        // Check mapping first
        if let mappedName = mapping.categoryMappings[name] {
            return await resolveCategoryByName(
                mappedName,
                type: type
            )
        }

        // Resolve by actual name
        return await resolveCategoryByName(
            name,
            type: type
        )
    }

    private func resolveCategoryByName(
        _ name: String,
        type: TransactionType
    ) async -> CategoryResolutionResult {

        // Check cache (lowercased key — case-insensitive)
        if let cachedId = cache.getCategory(name: name, type: type) {
            // Return the STORED category name (may differ in case from input)
            let storedName = transactionStore.categories.first(where: { $0.id == cachedId })?.name ?? name
            return .existing(id: cachedId, name: storedName)
        }

        // Check TransactionStore (Single Source of Truth) — case-insensitive like accounts/subcategories
        let nameLower = name.lowercased()
        if let existing = transactionStore.categories.first(where: {
            $0.name.lowercased() == nameLower && $0.type == type
        }) {
            cache.cacheCategory(name: name, type: type, id: existing.id)
            return .existing(id: existing.id, name: existing.name)
        }

        // Create new category directly in TransactionStore
        let iconName = CategoryIcon.iconName(
            for: name,
            type: type,
            customCategories: transactionStore.categories
        )
        let colorHex = CategoryColors.hexColor(
            for: name,
            customCategories: transactionStore.categories
        )
        let hexString = colorToHex(colorHex)

        let newCategory = CustomCategory(
            name: name,
            iconSource: .sfSymbol(iconName),
            colorHex: hexString,
            type: type
        )

        transactionStore.addCategory(newCategory)
        cache.cacheCategory(name: name, type: type, id: newCategory.id)


        return .created(id: newCategory.id, name: name)
    }

    // MARK: - Subcategory Resolution

    func resolveSubcategories(
        names: [String],
        categoryId: String
    ) async -> [SubcategoryResolutionResult] {

        var results: [SubcategoryResolutionResult] = []
        results.reserveCapacity(names.count)

        for name in names {
            let result = await resolveSubcategory(
                name: name,
                categoryId: categoryId
            )
            results.append(result)
        }

        return results
    }

    private func resolveSubcategory(
        name: String,
        categoryId: String
    ) async -> SubcategoryResolutionResult {

        // Check cache
        if let cachedId = cache.getSubcategory(name: name) {
            // Ensure link exists in TransactionStore
            ensureCategorySubcategoryLink(categoryId: categoryId, subcategoryId: cachedId)
            return .existing(id: cachedId)
        }

        // Check TransactionStore (Single Source of Truth)
        if let existing = transactionStore.subcategories.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) {
            cache.cacheSubcategory(name: name, id: existing.id)
            ensureCategorySubcategoryLink(categoryId: categoryId, subcategoryId: existing.id)
            return .existing(id: existing.id)
        }

        // Create new subcategory directly in TransactionStore
        let newSubcategory = Subcategory(name: name)
        transactionStore.addSubcategory(newSubcategory)
        cache.cacheSubcategory(name: name, id: newSubcategory.id)

        // Create link
        ensureCategorySubcategoryLink(categoryId: categoryId, subcategoryId: newSubcategory.id)


        return .created(id: newSubcategory.id)
    }

    // MARK: - Transaction Conversion (merged from TransactionConverterService, Phase 37)

    /// Converts a validated CSVRow + resolved entity IDs into a Transaction value.
    /// Previously lived in `TransactionConverterService`. Merged here because:
    ///   • All entity IDs (accountId, categoryId, subcategoryIds) are resolved by this service,
    ///     so conversion is a natural continuation of the mapping step.
    ///   • Eliminates a dedicated 74-LOC wrapper class with no state.
    func convertRow(
        _ csvRow: CSVRow,
        accountId: String?,
        targetAccountId: String?,
        categoryName: String,
        categoryId: String,
        subcategoryIds: [String],
        rowIndex: Int
    ) -> Transaction {

        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: csvRow.date)

        // Generate deterministic createdAt (date + row offset for stable sorting)
        let createdAt = csvRow.date.timeIntervalSince1970 + Double(rowIndex) * 0.001

        // Prefer note for ID generation; fall back to category name
        let descriptionForID = csvRow.note?.isEmpty == false ? csvRow.note! : categoryName

        let transactionId = TransactionIDGenerator.generateID(
            date: dateString,
            description: descriptionForID,
            amount: csvRow.amount,
            type: csvRow.type,
            currency: csvRow.currency,
            createdAt: createdAt
        )

        let subcategoryName = csvRow.subcategoryNames.first

        // For non-transfers: targetCurrency/targetAmount columns carry convertedAmount
        // For transfers: they carry the actual target account currency/amount
        let isTransfer = csvRow.type == .internalTransfer
        let convertedAmount: Double? = !isTransfer ? csvRow.targetAmount : nil
        let targetCurrency: String? = isTransfer ? csvRow.targetCurrency : nil
        let targetAmount: Double? = isTransfer ? csvRow.targetAmount : nil

        return Transaction(
            id: transactionId,
            date: dateString,
            description: csvRow.note ?? "",
            amount: csvRow.amount,
            currency: csvRow.currency,
            convertedAmount: convertedAmount,
            type: csvRow.type,
            category: categoryName,
            subcategory: subcategoryName,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: nil,         // resolved by CSVImportCoordinator after batch add
            targetAccountName: nil,   // resolved by CSVImportCoordinator after batch add
            targetCurrency: targetCurrency,
            targetAmount: targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: createdAt
        )
    }

    // MARK: - Helper Methods

    private func ensureCategorySubcategoryLink(categoryId: String, subcategoryId: String) {
        // Check if link already exists
        let linkExists = transactionStore.categorySubcategoryLinks.contains(where: {
            $0.categoryId == categoryId && $0.subcategoryId == subcategoryId
        })

        guard !linkExists else { return }

        // Create new link
        let link = CategorySubcategoryLink(categoryId: categoryId, subcategoryId: subcategoryId)
        var updatedLinks = transactionStore.categorySubcategoryLinks
        updatedLinks.append(link)
        transactionStore.updateCategorySubcategoryLinks(updatedLinks)

    }

    private func colorToHex(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
