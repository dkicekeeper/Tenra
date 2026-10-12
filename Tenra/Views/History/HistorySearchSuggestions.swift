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

import SwiftUI

struct HistorySearchSuggestions: ViewModifier {
    @Binding var text: String
    let categories: [CustomCategory]
    let subcategories: [Subcategory]

    @AppStorage("history.recentSearches") private var recent = RecentSearches()

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
        }
    }
}
