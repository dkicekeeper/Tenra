//
//  OnboardingCurrencyStep.swift
//  Tenra
//
//  Step 1: choose the base currency. Uses the shared CurrencyListContent
//  which exposes a native `.searchable` field in the nav-bar drawer.
//

import SwiftUI

struct OnboardingCurrencyStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingPageContainer(
            progressStep: 1,
            title: String(localized: "onboarding.currency.title"),
            subtitle: String(localized: "onboarding.currency.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: true,
            onPrimaryTap: {
                Task { await vm.advanceToAccountStep() }
            },
            onSkip: {
                Task { await vm.skip() }
            }
        ) {
            CurrencyListContent(selectedCurrency: vm.draftCurrency) { code in
                vm.draftCurrency = code
            }
            .padding(.top, AppSpacing.md)
        }
    }
}

#Preview("Onboarding — Currency") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingCurrencyStep(vm: vm)
    }
}
