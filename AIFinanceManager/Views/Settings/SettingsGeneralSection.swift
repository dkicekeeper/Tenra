//
//  SettingsGeneralSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI
import PhotosUI

/// Props-based General section for Settings
/// Single Responsibility: Group general settings (currency, wallpaper)
struct SettingsGeneralSection: View {
    // MARK: - Props

    let selectedCurrency: String
    let availableCurrencies: [String]
    let hasWallpaper: Bool
    @Binding var selectedPhoto: PhotosPickerItem?
    let onCurrencyChange: (String) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onWallpaperRemove: () async -> Void

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.general"))) {
            // Base Currency Picker
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: AppIconSize.md))
                    .foregroundStyle(AppColors.accent)

                Text(String(localized: "settings.baseCurrency"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Menu {
                    ForEach(availableCurrencies, id: \.self) { currency in
                        Button {
                            onCurrencyChange(currency)
                        } label: {
                            HStack {
                                Text(Formatting.currencySymbol(for: currency))
                                if selectedCurrency == currency {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(Formatting.currencySymbol(for: selectedCurrency))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.secondaryBackground)
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, AppSpacing.xs)

            WallpaperPickerRow(
                hasWallpaper: hasWallpaper,
                selectedPhoto: $selectedPhoto,
                onPhotoChange: onPhotoChange,
                onRemove: onWallpaperRemove
            )
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedPhoto: PhotosPickerItem? = nil

        var body: some View {
            List {
                SettingsGeneralSection(
                    selectedCurrency: "KZT",
                    availableCurrencies: ["KZT", "USD", "EUR", "RUB"],
                    hasWallpaper: true,
                    selectedPhoto: $selectedPhoto,
                    onCurrencyChange: { _ in },
                    onPhotoChange: { _ in },
                    onWallpaperRemove: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
