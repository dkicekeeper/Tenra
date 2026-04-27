//
//  CategoryPresetCell.swift
//  Tenra

import SwiftUI

struct CategoryPresetCell: View {
    let preset: CategoryPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(hex: preset.colorHex))
                        .frame(width: 56, height: 56)
                        .overlay(
                            iconImage
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(AppColors.accent, lineWidth: isSelected ? 2 : 0)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.accent, AppColors.backgroundPrimary)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(String(localized: String.LocalizationValue(preset.nameKey)))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .opacity(isSelected ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(AppAnimation.contentSpring, value: isSelected)
    }

    @ViewBuilder
    private var iconImage: some View {
        switch preset.iconSource {
        case .sfSymbol(let name):
            Image(systemName: name)
        case .brandService:
            Image(systemName: "questionmark.circle")  // not expected for presets
        }
    }
}
