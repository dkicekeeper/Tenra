//
//  CategoryBreakdownRow.swift
//  Tenra
//
//  Shared category breakdown row for Insights detail screens. Adapter over
//  DesignKit's `BreakdownRow` (which also ships `AmountPercentageView`): maps the
//  breakdown item and localizes its category name.
//
//  Navigation is left to the caller: wrap this row in a `NavigationLink` and pass
//  `showsChevron: true` so it renders the native disclosure indicator.
//

import SwiftUI

/// One category row in an Insights breakdown: tinted icon, name, up to three
/// subcategory names, and a trailing amount + share. Pass `showsChevron: true`
/// when the row is wrapped in a `NavigationLink` to show the native chevron.
struct CategoryBreakdownRow: View {
    let item: CategoryBreakdownItem
    let currency: String
    var showsChevron: Bool = false

    var body: some View {
        BreakdownRow(
            iconSource: item.iconSource,
            color: item.color,
            // `categoryName` carries the raw grouping key (it drives the deep-dive
            // lookup), so the technical "Loan Payment" key is localized here.
            title: CategoryDisplay.displayName(for: item.categoryName, type: .expense),
            subtitle: item.subcategories.isEmpty
                ? nil
                : item.subcategories.prefix(3).map(\.name).joined(separator: ", "),
            amount: item.amount,
            currency: currency,
            percentage: item.percentage,
            showsChevron: showsChevron
        )
    }
}

// MARK: - Previews

#Preview("With chevron") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 0) {
                CategoryBreakdownRow(
                    item: .preview(name: "Food", color: AppColors.warning, icon: "fork.knife", amount: 85_000, pct: 42),
                    currency: "KZT",
                    showsChevron: true
                )
                CategoryBreakdownRow(
                    item: .preview(name: "Transport", color: AppColors.accent, icon: "car.fill", amount: 38_000, pct: 19),
                    currency: "KZT",
                    showsChevron: true
                )
            }
            .screenPadding()
        }
    }
}

#Preview("Without chevron") {
    ScrollView {
        VStack(spacing: 0) {
            CategoryBreakdownRow(
                item: .preview(name: "Shopping", color: AppColors.income, icon: "bag.fill", amount: 56_000, pct: 28),
                currency: "KZT"
            )
        }
        .screenPadding()
    }
}

// MARK: - Preview helper

private extension CategoryBreakdownItem {
    static func preview(name: String, color: Color, icon: String, amount: Double, pct: Double) -> CategoryBreakdownItem {
        CategoryBreakdownItem(
            id: name,
            categoryName: name,
            amount: amount,
            percentage: pct,
            color: color,
            iconSource: .sfSymbol(icon),
            subcategories: []
        )
    }
}
