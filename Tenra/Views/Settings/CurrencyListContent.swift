//
//  CurrencyListContent.swift
//  Tenra
//
//  Reusable currency picker. Uses `ScrollView + VStack` (not `List`) so the
//  parent surface — including the onboarding accent-glow background — shows
//  through without being painted over by `List`'s grouped-background grey.
//  `.searchable` is attached in nav-bar drawer placement (.automatic) — drawer
//  hides on scroll and reveals on pull-down, same pattern for both Settings
//  and onboarding (the onboarding-specific tweaks live in the parent container).
//

import SwiftUI

struct CurrencyListContent: View {
    let selectedCurrency: String
    let onTap: (String) -> Void

    @State private var searchText = ""

    // MARK: - Filtered Data

    private var filteredCurrencies: [CurrencyInfo] {
        guard !searchText.isEmpty else { return CurrencyInfo.allCurrencies }
        let query = searchText.lowercased()
        return CurrencyInfo.allCurrencies.filter {
            $0.code.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    private var showPopularSection: Bool { searchText.isEmpty }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if showPopularSection {
                    section(
                        title: String(localized: "currency.popular"),
                        items: CurrencyInfo.popularCurrencies
                    )
                }
                section(
                    title: String(localized: "currency.all"),
                    items: filteredCurrencies
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: String(localized: "currency.searchPrompt")
        )
    }

    // MARK: - Section

    @ViewBuilder
    private func section(title: String, items: [CurrencyInfo]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.sm)

            // LazyVStack defers row construction until rows scroll into view.
            // With ~150 currencies this keeps the initial render cheap.
            LazyVStack(spacing: 0) {
                ForEach(items) { currency in
                    currencyRow(currency)
                    if currency.id != items.last?.id {
                        Divider()
                            .padding(.leading, AppSpacing.lg)
                    }
                }
            }
            .background(
                AppColors.bgCard,
                in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            )
        }
    }

    // MARK: - Row

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            HapticManager.selection()
            onTap(currency.code)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.code)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(currency.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text(currency.symbol)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                if currency.code == selectedCurrency {
                    Image(systemName: "checkmark")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
