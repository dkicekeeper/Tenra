//
//  CategoryStyleCache.swift
//  Tenra
//
//  Process-wide cache of per-category visual data (colours + icon name).
//
//  Read path is O(1):
//   • Hit:  one hashmap lookup, returns the pre-computed `CategoryStyleData`.
//   • Miss: one O(N_cat) lookup into the passed `customCategories` (still
//           bounded — N ≤ ~30), then memoise.
//
//  Invalidation is explicit and surgical: `TransactionStore.updateCategory`
//  decides whether a mutation actually touched a visual property
//  (icon / color / name / type) and calls `invalidate(name:type:)` accordingly.
//  Pure budget edits do NOT thrash the cache.
//
//  The pre-refactor version rebuilt a `Set<String>` snapshot on EVERY
//  `getStyleData` call to detect external mutations — O(N_cat) allocs per
//  row render. That logic is gone; callers that change categories must call
//  `invalidate(...)` (TransactionStore does this for them).
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

/// Singleton cache for category styles.
@MainActor
final class CategoryStyleCache {

    // MARK: - Singleton

    static let shared = CategoryStyleCache()
    private init() {}

    // MARK: - Cache

    /// Cache key: "categoryName_transactionType".
    private var cache: [String: CategoryStyleData] = [:]

    // MARK: - Public Methods

    /// Get or compute style data for a category.
    /// - Parameters:
    ///   - category: Category name (case-preserved).
    ///   - type: Transaction type.
    ///   - customCategories: All custom categories — used only on cache miss.
    /// - Returns: Pre-computed style data.
    func getStyleData(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        let key = Self.cacheKey(category: category, type: type)
        if let cached = cache[key] { return cached }

        let styleData = computeStyleData(
            category: category,
            type: type,
            customCategories: customCategories
        )
        cache[key] = styleData
        return styleData
    }

    /// Drop every cached entry. Called when the categories array is wholesale
    /// reloaded (e.g. CSV import, syncCategories) — the cheap nuclear option.
    func invalidateCache() {
        cache.removeAll()
    }

    /// Drop a single category's cached style — used by TransactionStore.updateCategory
    /// when icon / colour / name / type changes for a specific category.
    /// Both rawValue casts are O(1).
    func invalidate(name: String, type: TransactionType) {
        cache.removeValue(forKey: Self.cacheKey(category: name, type: type))
    }

    /// Legacy single-key invalidation. Retained for callers in unrelated codepaths;
    /// internally just forwards to the modern overload.
    func invalidateCategory(_ category: String, type: TransactionType) {
        invalidate(name: category, type: type)
    }

    // MARK: - Private Helpers

    private static func cacheKey(category: String, type: TransactionType) -> String {
        "\(category)_\(type.rawValue)"
    }

    private func computeStyleData(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        // System types fall back to a clean typed style with an SF Symbol when the user
        // hasn't picked a real category. If a custom category IS selected, the regular
        // branch below picks up its color/icon.
        if let systemStyle = systemTypeStyle(category: category, type: type, customCategories: customCategories) {
            return systemStyle
        }

        // Regular category — both income and expense use the per-category color
        // (resolved from customCategories, or a deterministic palette hash for
        // unknown names). Previously income was forced to a single green tint,
        // which collapsed every income card's icon to the same color.
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

    /// Returns a baked-in style for system transaction types (loan / deposit) when
    /// the user is still on the technical default category — otherwise nil so the
    /// regular custom-category lookup runs.
    private func systemTypeStyle(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData? {
        let pickedCustom = customCategories.contains { $0.name == category }
        if pickedCustom { return nil }

        switch type {
        case .loanPayment, .loanEarlyRepayment:
            return systemStyle(tint: AppColors.expense, iconName: "creditcard.fill")
        case .depositTopUp:
            return systemStyle(tint: AppColors.income, iconName: "banknote.fill")
        case .depositWithdrawal:
            return systemStyle(tint: AppColors.expense, iconName: "banknote.fill")
        case .depositInterestAccrual:
            return systemStyle(tint: AppColors.income, iconName: "percent")
        case .internalTransfer:
            return systemStyle(tint: .gray, iconName: "arrow.left.arrow.right")
        default:
            return nil
        }
    }

    private func systemStyle(tint: Color, iconName: String) -> CategoryStyleData {
        CategoryStyleData(
            coinColor: tint.opacity(0.3),
            coinBorderColor: tint.opacity(0.6),
            iconColor: tint,
            primaryColor: tint,
            lightBackgroundColor: tint.opacity(0.15),
            iconName: iconName
        )
    }
}

// MARK: - CategoryStyleHelper Extension

extension CategoryStyleHelper {
    /// Create helper with cached style data.
    /// OPTIMIZATION: Use this instead of direct init for repeated renders.
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
