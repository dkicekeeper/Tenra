//
//  CategoryStyleCache.swift
//  Tenra
//
//  Global singleton cache for CategoryStyleHelper to avoid recreating on every render
//  OPTIMIZATION: Reduces object creation from 60fps × N categories to O(1) lookups
//

import SwiftUI

/// Pre-computed category style data
struct CategoryStyleData: Equatable {
    let coinColor: Color
    let coinBorderColor: Color
    let iconColor: Color
    let primaryColor: Color
    let lightBackgroundColor: Color
    let iconName: String
}

extension CategoryStyleData {
    /// Neutral grey fallback used by EntityDetailScaffold's default styleHelper
    /// when no per-transaction style is provided by the caller.
    static let fallback = CategoryStyleData(
        coinColor: .gray.opacity(0.3),
        coinBorderColor: .gray.opacity(0.6),
        iconColor: .gray,
        primaryColor: .gray,
        lightBackgroundColor: .gray.opacity(0.15),
        iconName: "questionmark.circle.fill"
    )
}

/// Singleton cache for category styles
@MainActor
final class CategoryStyleCache {

    // MARK: - Singleton

    static let shared = CategoryStyleCache()

    private init() {}

    // MARK: - Cache

    /// Cache key: "categoryName_transactionType"
    private var cache: [String: CategoryStyleData] = [:]

    /// ✅ OPTIMIZATION: Categories snapshot using Set for stable comparison
    /// Avoids false invalidations from array order changes
    private var cachedCategoriesSnapshot: Set<String> = []

    // MARK: - Public Methods

    /// Get or compute style data for a category
    /// - Parameters:
    ///   - category: Category name
    ///   - type: Transaction type
    ///   - customCategories: All custom categories
    /// - Returns: Pre-computed style data
    func getStyleData(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        // ✅ OPTIMIZATION: Check if categories actually changed using Set comparison
        // This avoids false invalidations from array reordering.
        // ✅ FIX: Use displayIdentifier instead of String(describing:) for deterministic
        // strings — guaranteed to change when icon or color is updated.
        let currentSnapshot = Set(customCategories.map { "\($0.id)_\($0.colorHex)_\($0.iconSource.displayIdentifier)" })
        if currentSnapshot != cachedCategoriesSnapshot {
            cache.removeAll()
            cachedCategoriesSnapshot = currentSnapshot
        }

        // Generate cache key
        let key = "\(category)_\(type.rawValue)"

        // Return from cache if exists
        if let cached = cache[key] {
            return cached
        }

        // Compute style data
        let styleData = computeStyleData(
            category: category,
            type: type,
            customCategories: customCategories
        )

        // Cache it
        cache[key] = styleData


        return styleData
    }

    /// Invalidate entire cache (call when categories change)
    func invalidateCache() {
        _ = cache.count
        cache.removeAll()
        cachedCategoriesSnapshot.removeAll()

    }

    /// Invalidate specific category
    /// - Parameters:
    ///   - category: Category name
    ///   - type: Transaction type
    func invalidateCategory(_ category: String, type: TransactionType) {
        let key = "\(category)_\(type.rawValue)"
        cache.removeValue(forKey: key)

    }

    // MARK: - Private Helpers

    /// Compute style data from scratch
    private func computeStyleData(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        // Special case: income
        if type == .income {
            return CategoryStyleData(
                coinColor: AppColors.income.opacity(0.3),
                coinBorderColor: AppColors.income.opacity(0.6),
                iconColor: AppColors.income,
                primaryColor: AppColors.income,
                lightBackgroundColor: AppColors.income.opacity(0.15),
                iconName: CategoryIcon.iconName(for: category, type: type, customCategories: customCategories)
            )
        }

        // Regular category
        let baseColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: customCategories)

        return CategoryStyleData(
            coinColor: CategoryColors.hexColor(for: category, opacity: 0.3, customCategories: customCategories),
            coinBorderColor: CategoryColors.hexColor(for: category, opacity: 0.6, customCategories: customCategories),
            iconColor: baseColor,
            primaryColor: baseColor,
            lightBackgroundColor: CategoryColors.hexColor(for: category, opacity: 0.15, customCategories: customCategories),
            iconName: CategoryIcon.iconName(for: category, type: type, customCategories: customCategories)
        )
    }
}

// MARK: - CategoryStyleHelper Extension

extension CategoryStyleHelper {
    /// Create helper with cached style data
    /// OPTIMIZATION: Use this instead of direct init for repeated renders
    static func cached(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        CategoryStyleCache.shared.getStyleData(
            category: category,
            type: type,
            customCategories: customCategories
        )
    }
}
