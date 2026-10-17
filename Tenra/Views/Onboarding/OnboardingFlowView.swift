//
//  OnboardingFlowView.swift
//  Tenra
//
//  Root view of the onboarding experience: a single NavigationStack hosting
//  the animated welcome screen at the root and the 3-step data-collection
//  flow as pushed destinations.
//

import SwiftUI

struct OnboardingFlowView: View {
    @State private var vm: OnboardingViewModel

    init(coordinator: AppCoordinator) {
        _vm = State(wrappedValue: OnboardingViewModel(coordinator: coordinator))
    }

    var body: some View {
        NavigationStack(path: $vm.path) {
            OnboardingWelcomeStep(vm: vm)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .currency:
                        OnboardingCurrencyStep(vm: vm)
                    case .account:
                        OnboardingAccountStep(vm: vm)
                    case .categories:
                        OnboardingCategoriesStep(vm: vm)
                    }
                }
        }
        .softScrollEdges()
    }
}

#Preview("Onboarding Flow") {
    OnboardingFlowView(coordinator: AppCoordinator())
}
