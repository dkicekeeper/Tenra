//
//  OnboardingCurrencyStep.swift
//  Tenra
//
//  Step 1: choose the base currency. Uses the shared CurrencyListContent (native
//  `.searchable` drawer). Wrapping it in an outer ScrollView keeps the navigation
//  bar transparent over the onboarding accent-glow (no scroll-edge plate); that
//  ScrollView carries the list's grey, so the page is one colour up to the bar.
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
            },
            stepSymbols: OnboardingViewModel.stepSymbols
        ) {
            ScrollView {
                CurrencyListContent(selectedCurrency: vm.draftCurrency) { code in
                    vm.draftCurrency = code
                }
                .padding(.top, AppSpacing.md)
            }
            // CurrencyList paints its own scroll the grouped grey; the page under the bar takes
            // the same, else a white band sits between the bar and the cards.
            .background(AppColors.Background.baseAlt)
        }
    }
}

#Preview("Onboarding — Currency") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingCurrencyStep(vm: vm)
    }
}
