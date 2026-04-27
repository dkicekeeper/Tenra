//
//  CurrencyPickerView.swift
//  Tenra
//
//  Full-screen searchable currency list with "Popular" and "All" sections.
//

import SwiftUI

struct CurrencyPickerView: View {
    let selectedCurrency: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CurrencyListContent(selectedCurrency: selectedCurrency) { code in
            onSelect(code)
            dismiss()
        }
        .navigationTitle(String(localized: "currency.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CurrencyPickerView(selectedCurrency: "KZT") { code in
            print("Selected: \(code)")
        }
    }
}
