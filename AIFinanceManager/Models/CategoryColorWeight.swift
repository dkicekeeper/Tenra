//
//  CategoryColorWeight.swift
//  AIFinanceManager
//
//  Lightweight value type representing a single category's
//  proportional weight in total expenses — used to drive the
//  Apple Card-style gradient background in TransactionsSummaryCard.
//

import Foundation

/// A category name paired with its share of total expenses (0.0–1.0).
///
/// Sendable and value-type so it is safe to pass back from `Task.detached`
/// to the MainActor without any bridging. Colors are intentionally NOT
/// stored here — they are resolved in the View layer via
/// `CategoryColors.hexColor(for:customCategories:)` on the MainActor.
struct CategoryColorWeight: Sendable, Hashable {
    /// The category name used to resolve its color via `CategoryColors`.
    let category: String
    /// Proportion of total expenses: `categoryAmount / totalExpenses`.
    /// Ranges from 0.0 (no spend) to 1.0 (100 % of spend).
    let weight: Double
}
