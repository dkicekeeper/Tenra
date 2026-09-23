//
//  CategorySuggestionProvider.swift
//  Tenra
//
//  Combines the three suggestion tiers for not-yet-saved transactions:
//    1. the user's own history for the same merchant (only if that category
//       still exists),
//    2. the curated brand list (`CategorySuggestionService.brandPresets`),
//    3. the voice-input keyword dictionary (`VoiceInputParser.keywordCategory`).
//  Tiers 2 and 3 are expense-only. Every candidate is resolved against the
//  user's categories through `TransactionDraftService.resolveCategory`; a
//  result that falls back to "Other" or to uncategorized counts as no
//  suggestion, so a miss leaves the row exactly as before.
//

import Foundation

@MainActor
enum CategorySuggestionProvider {

    /// Suggestions keyed by transaction id. Only `.expense` / `.income` rows get
    /// one. The history index is built off the main actor on every call and is
    /// deliberately NOT cached: it must reflect the store at import time.
    static func suggestions(
        for transactions: [Transaction],
        history: [Transaction],
        categories: [CustomCategory],
        keywordMatcher: (String) -> String?
    ) async -> [String: String] {
        let candidates = transactions.filter { $0.type == .expense || $0.type == .income }
        guard !candidates.isEmpty else { return [:] }

        let index = await Task.detached(priority: .userInitiated) {
            CategorySuggestionService.buildHistoryIndex(from: history)
        }.value

        var result: [String: String] = [:]
        for tx in candidates {
            if let name = suggestion(
                for: tx.description,
                type: tx.type,
                index: index,
                categories: categories,
                keywordMatcher: keywordMatcher
            ) {
                result[tx.id] = name
            }
        }
        return result
    }

    static func suggestion(
        for description: String,
        type: TransactionType,
        index: CategorySuggestionService.HistoryIndex,
        categories: [CustomCategory],
        keywordMatcher: (String) -> String?
    ) -> String? {
        if let learned = CategorySuggestionService.historyCategory(for: description, type: type, in: index),
           categories.contains(where: { $0.type == type && $0.name == learned }) {
            return learned
        }

        guard type == .expense else { return nil }

        if let presetId = CategorySuggestionService.brandPresetId(for: description),
           let preset = CategoryPreset.defaultExpense.first(where: { $0.id == presetId }),
           let name = accepted(String(localized: String.LocalizationValue(preset.nameKey)), type: type, in: categories) {
            return name
        }

        if let raw = keywordMatcher(description),
           let name = accepted(raw, type: type, in: categories) {
            return name
        }

        return nil
    }

    /// The user's category a raw name resolves to, or nil when resolution only
    /// reaches the "Other" / uncategorized fallbacks.
    private static func accepted(_ raw: String, type: TransactionType, in categories: [CustomCategory]) -> String? {
        let resolution = TransactionDraftService.resolveCategory(named: raw, type: type, in: categories)
        guard !resolution.name.isEmpty,
              resolution.name != String(localized: "category.other") else { return nil }
        return resolution.name
    }
}
