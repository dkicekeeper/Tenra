//
//  OnboardingCategoryGrid.swift
//  Tenra
//
//  Selection grid built on top of `CategoryChip` — the same chip that powers
//  the production `CategoryGridView`, but driven by `SelectablePreset` instead
//  of `CategoryDisplayData`.
//

import SwiftUI

struct OnboardingCategoryGrid: View {
    @Binding var presets: [SelectablePreset]
    var columns: Int? = nil

    private var gridColumns: [GridItem] {
        if let columns {
            return Array(
                repeating: GridItem(.flexible(), spacing: AppSpacing.md),
                count: columns
            )
        }
        return [GridItem(.adaptive(minimum: 70, maximum: 120), spacing: AppSpacing.md)]
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: AppSpacing.xxl) {
            ForEach($presets) { $selectable in
                cell(for: $selectable)
            }
        }
        .padding(AppSpacing.xxs)
    }

    @ViewBuilder
    private func cell(for selectable: Binding<SelectablePreset>) -> some View {
        let preset = selectable.wrappedValue.preset
        let isSelected = selectable.wrappedValue.isSelected
        let name = String(localized: String.LocalizationValue(preset.nameKey))
        let color = Color(hex: preset.colorHex)
        let iconName: String = {
            if case let .sfSymbol(symbol) = preset.iconSource { return symbol }
            return "questionmark.circle"
        }()

        CategoryChip(
            category: name,
            type: preset.type,
            customCategories: [],
            isSelected: isSelected,
            onTap: {
                selectable.wrappedValue.isSelected.toggle()
            },
            budgetProgress: nil,
            iconName: iconName,
            iconColor: color
        )
        .opacity(isSelected ? 1 : 0.55)
        .animation(AppAnimation.contentSpring, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview("Onboarding Category Grid") {
    @Previewable @State var presets = CategoryPreset.defaultExpense.map {
        $0.makeSelectable(isSelected: true)
    }

    return ScrollView {
        OnboardingCategoryGrid(presets: $presets)
            .padding()
    }
}
