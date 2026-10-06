//
//  CurrencyListContent.swift
//  Tenra
//
//  Adapter over DesignKit's CurrencyList (1.10.0), which keeps the ScrollView of cards
//  (the onboarding accent glow shows through) and the search in the nav-bar drawer.
//

import SwiftUI

struct CurrencyListContent: View {
    let selectedCurrency: String
    let onTap: (String) -> Void

    var body: some View {
        // DesignKit's CurrencyList (1.10.0): the same cards, search and rows.
        CurrencyList(selection: selectedCurrency, onSelect: onTap)
    }
}
