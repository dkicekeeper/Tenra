//
//  CategoryBreakdownRow.swift
//  Tenra
//
//  Shared category breakdown row for Insights detail screens.
//  Replaces the two duplicated `categoryRow` builders in InsightDetailView
//  (static breakdown) and PagedCategoryBreakdownView (paged breakdown).
//
//  Navigation is left to the caller: wrap this row in a `NavigationLink` and pass
//  `showsChevron: true` so it renders the native disclosure indicator.
//

import SwiftUI

/// Trailing "amount + percentage" stack shared by category / subcategory rows.
struct AmountPercentageView: View {
    let amount: Double
    let currency: String
    let percentage: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xs) {
            FormattedAmountText(amount: amount, currency: currency, color: AppColors.textPrimary)
            Text(String(format: "%.1f%%", percentage))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

/// One category row in an Insights breakdown: tinted icon, name, up to three
/// subcategory names, and a trailing amount + share. Pass `showsChevron: true`
/// when the row is wrapped in a `NavigationLink` to show the native chevron.
struct CategoryBreakdownRow: View {
    let item: CategoryBreakdownItem
    let currency: String
    var showsChevron: Bool = false

    var body: some View {
        // Built on UniversalRow(.info) — same base as InsightEntityRow, so both
        // breakdown rows share icon slot, spacing (md) and vertical padding (sm).
        UniversalRow(
            config: .info,
            leadingIcon: .custom(
                source: item.iconSource,
                style: .circle(
                    size: AppIconSize.xxl,
                    tint: .monochrome(item.color),
                    backgroundColor: item.color.opacity(0.15)
                )
            )
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.categoryName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if !item.subcategories.isEmpty {
                    Text(item.subcategories.prefix(3).map(\.name).joined(separator: ", "))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
        } trailing: {
            HStack(spacing: AppSpacing.md) {
                AmountPercentageView(amount: item.amount, currency: currency, percentage: item.percentage)
                if showsChevron {
                    DisclosureChevron()
                }
            }
        }
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
