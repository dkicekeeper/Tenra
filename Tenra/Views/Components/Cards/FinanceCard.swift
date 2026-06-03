//
//  FinanceCard.swift
//  Tenra
//
//  Shared shell for the home-screen finance-product entry cards (accounts,
//  deposits, loans, subscriptions, categories, subcategories). Each concrete
//  card supplies its own title, empty-state copy, hero value, subtitle and
//  trailing icon facepile; the shell owns the identical layout, empty-state
//  swap, padding and glass styling.
//

import SwiftUI

/// Home-screen finance section card: title + (hero value + subtitle) on the
/// left, an icon facepile on the right, with a compact empty state swapped in
/// when there's no data. Container owns layout/padding/`.cardStyle()`.
struct FinanceCard<Hero: View, Trailing: View>: View {
    let title: String
    let isEmpty: Bool
    let emptyTitle: String
    /// Localized count / context line shown under the hero value.
    let subtitle: String
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        isEmpty: Bool,
        emptyTitle: String,
        subtitle: String,
        @ViewBuilder hero: @escaping () -> Hero,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.subtitle = subtitle
        self.hero = hero
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)

                if isEmpty {
                    EmptyStateView(title: emptyTitle, style: .compact)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        hero()
                        Text(subtitle)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isEmpty {
                trailing()
            }
        }
        .animation(AppAnimation.gentleSpring, value: isEmpty)
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

/// Hero amount that shows a redacted placeholder while an async total is being
/// computed, then cross-fades to the formatted value. Used by the finance cards
/// whose total requires FX conversion (accounts, deposits, subscriptions).
struct RedactableAmount: View {
    let amount: Double
    let currency: String
    let isLoading: Bool
    var fontSize: Font = AppTypography.h2

    var body: some View {
        ZStack {
            if isLoading {
                Text("0000.00")
                    .font(fontSize)
                    .fontWeight(.bold)
                    .redacted(reason: .placeholder)
                    .transition(.opacity)
            } else {
                FormattedAmountText(
                    amount: amount,
                    currency: currency,
                    fontSize: fontSize,
                    fontWeight: .bold,
                    color: AppColors.textPrimary
                )
                .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: isLoading)
    }
}

// MARK: - Previews

private func previewFacepile() -> some View {
    PackedCircleIconsView(items: [
        PackedCircleItem(id: "1", iconSource: .sfSymbol("creditcard.fill"), amount: 1_250_000, tint: AppColors.accent),
        PackedCircleItem(id: "2", iconSource: .sfSymbol("banknote.fill"), amount: 480_000, tint: AppColors.success),
        PackedCircleItem(id: "3", iconSource: .sfSymbol("wallet.bifold.fill"), amount: 120_000, tint: AppColors.warning)
    ])
}

#Preview("Amount hero") {
    FinanceCard(
        title: "Accounts",
        isEmpty: false,
        emptyTitle: "No accounts",
        subtitle: "3 accounts"
    ) {
        RedactableAmount(amount: 1_850_000, currency: "KZT", isLoading: false)
    } trailing: {
        previewFacepile()
    }
    .screenPadding()
}

#Preview("Amount hero — loading") {
    FinanceCard(
        title: "Subscriptions",
        isEmpty: false,
        emptyTitle: "No subscriptions",
        subtitle: "5 active"
    ) {
        RedactableAmount(amount: 0, currency: "KZT", isLoading: true)
    } trailing: {
        previewFacepile()
    }
    .screenPadding()
}

#Preview("Count hero") {
    FinanceCard(
        title: "Categories",
        isEmpty: false,
        emptyTitle: "No categories",
        subtitle: "12 categories"
    ) {
        Text("12")
            .font(AppTypography.h2)
            .fontWeight(.bold)
            .foregroundStyle(AppColors.textPrimary)
    } trailing: {
        previewFacepile()
    }
    .screenPadding()
}

#Preview("Empty") {
    FinanceCard(
        title: "Loans",
        isEmpty: true,
        emptyTitle: "No loans yet",
        subtitle: ""
    ) {
        EmptyView()
    } trailing: {
        EmptyView()
    }
    .screenPadding()
}
