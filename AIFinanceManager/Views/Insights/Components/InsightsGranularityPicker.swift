//
//  InsightsGranularityPicker.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights — Granularity picker
//  Horizontal scrolling pill-button picker for selecting
//  Week / Month / Quarter / Year / All Time grouping.
//

import SwiftUI

struct InsightsGranularityPicker: View {
    @Binding var selected: InsightGranularity
    var onSelect: ((InsightGranularity) -> Void)? = nil

    var body: some View {
        UniversalCarousel(config: .filter) {
            ForEach(InsightGranularity.allCases) { granularity in
                GranularityChip(
                    granularity: granularity,
                    isSelected: selected == granularity
                ) {
                    HapticManager.light()
                    withAnimation(AppAnimation.adaptiveSpring) {
                        selected = granularity
                    }
                    onSelect?(granularity)
                }
            }
        }
    }
}

// MARK: - GranularityChip

private struct GranularityChip: View {
    let granularity: InsightGranularity
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: granularity.icon)
                    .font(AppTypography.caption.weight(.semibold))
                Text(granularity.shortName)
                    .font(AppTypography.bodySmall)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? AppColors.staticWhite : AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                Group {
                    if isSelected {
                        AppColors.accent
                    } else {
                        AppColors.surface
                    }
                }
                .clipShape(Capsule())
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(granularity.displayName)
    }
}

// icon is now defined in InsightGranularity.swift (internal extension)

// MARK: - Preview

#Preview {
    @Previewable @State var selected: InsightGranularity = .month
    VStack(spacing: AppSpacing.lg) {
        InsightsGranularityPicker(selected: $selected)
        Text("Selected: \(selected.displayName)")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
    }
    .padding(.vertical, AppSpacing.lg)
}
