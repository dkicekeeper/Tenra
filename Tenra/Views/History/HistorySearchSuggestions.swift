//
//  HistorySearchSuggestions.swift
//  Tenra
//
//  History's search suggestions: DesignKit's `.dsSearchSuggestions` (3.5.0) in the system
//  search's own suggestion list. The recent queries are kept here (`@AppStorage`); the
//  suggestions are the user's categories and subcategories, which the search matches by name
//  (TransactionPaginationController), so a tap fills the field and the list filters as usual.
//  Accounts are left out: the text search does not match them.
//
//  Merchants too (docs/plan-auto-capture.md §7): the ones the Wallet automation remembers, and
//  the frequent ones of the history (`merchantSamples`) that have a logo or a name the user
//  gave them, so the list is brands, not people paid by transfer. Shown under the clean or
//  given name with the logo; a tap fills `MerchantName.searchQuery`, text the description
//  search finds.
//

import SwiftUI

struct HistorySearchSuggestions: ViewModifier {
    @Binding var text: String
    let categories: [CustomCategory]
    let subcategories: [Subcategory]
    /// Frequent merchants of the history, each as one of its descriptions, most frequent first.
    var merchantSamples: [String] = []

    @AppStorage("history.recentSearches") private var recent = RecentSearches()
    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    func body(content: Content) -> some View {
        content.dsSearchSuggestions(text: $text, recent: $recent, suggestions: suggestions)
    }

    private var suggestions: [SearchSuggestion] {
        let categoryTitle = String(localized: "search.suggestion.category")
        let subcategoryTitle = String(localized: "search.suggestion.subcategory")
        return categories.map { category in
            SearchSuggestion(
                category.name,
                subtitle: categoryTitle,
                icon: category.iconSource,
                tint: category.color,
                id: "category-\(category.id)"
            )
        } + subcategories.map { subcategory in
            SearchSuggestion(
                subcategory.name,
                subtitle: subcategoryTitle,
                icon: .sfSymbol("tag"),
                id: "subcategory-\(subcategory.id)"
            )
        } + merchantSuggestions
    }

    private var merchantSuggestions: [SearchSuggestion] {
        let logos = MerchantLogoStore.shared
        let merchantTitle = String(localized: "search.suggestion.merchant")
        let remembered = MerchantCategoryMemory.shared.merchants.map(\.displayName)
        let branded = merchantSamples.filter {
            logos.iconSource(forDescription: $0) != nil || logos.customName(forDescription: $0) != nil
        }
        var seen = Set<String>()
        return (remembered + branded).compactMap { sample in
            let key = CategorySuggestionService.normalizedMerchant(sample)
            guard key.count >= CategorySuggestionService.minimumMerchantLength,
                  seen.insert(key).inserted else { return nil }
            return SearchSuggestion(
                logos.customName(forDescription: sample) ?? MerchantName.displayName(sample),
                subtitle: merchantTitle,
                icon: (showsMerchantLogos ? logos.iconSource(forDescription: sample) : nil) ?? .sfSymbol("storefront"),
                completion: MerchantName.searchQuery(sample),
                id: "merchant-\(key)"
            )
        }
    }
}
