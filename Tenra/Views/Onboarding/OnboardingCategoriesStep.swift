//
//  OnboardingCategoriesStep.swift
//  Tenra
//
//  Step 3: pick which preset expense categories to seed. Uses the shared
//  CategoryChip-based grid so visuals match the production category screen.
//

import SwiftUI

struct OnboardingCategoriesStep: View {
    @Bindable var vm: OnboardingViewModel

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
                Task { await vm.finish() }
            },
            onSkip: {
                Task { await vm.skip() }
            }
        ) {
            ScrollView {
                OnboardingCategoryGrid(presets: $vm.draftCategories)
                    .screenPadding()
                    .padding(.top, AppSpacing.md)
            }
        }
    }
}

#Preview("Onboarding — Categories") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingCategoriesStep(vm: vm)
    }
}
