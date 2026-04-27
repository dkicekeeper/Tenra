//
//  OnboardingCategoriesStep.swift
//  Tenra

import SwiftUI

struct OnboardingCategoriesStep: View {
    @Bindable var vm: OnboardingViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 3
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: count)
    }

    private var doneTitle: String {
        let count = vm.selectedPresetCount
        return String(format: String(localized: "onboarding.cta.doneWithCount"), count)
    }

    var body: some View {
        OnboardingPageContainer(
            progressStep: 3,
            title: String(localized: "onboarding.categories.title"),
            subtitle: String(localized: "onboarding.categories.subtitle"),
            primaryButtonTitle: doneTitle,
            primaryButtonEnabled: vm.canFinish,
            onPrimaryTap: {
                vm.finish()    // finish() is sync, NOT async
            }
        ) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                    ForEach(vm.draftCategories.indices, id: \.self) { idx in
                        let preset = vm.draftCategories[idx].preset
                        let isSelected = vm.draftCategories[idx].isSelected
                        CategoryPresetCell(preset: preset, isSelected: isSelected) {
                            vm.draftCategories[idx].isSelected.toggle()
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
        }
    }
}
