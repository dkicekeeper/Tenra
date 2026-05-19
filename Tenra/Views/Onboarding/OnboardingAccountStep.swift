//
//  OnboardingAccountStep.swift
//  Tenra
//
//  Step 2: create the first account. Uses `EditableHeroSection` for visual
//  parity with the production `AccountEditView`. The currency picker is
//  hidden — the user already picked their base currency in step 1.
//

import SwiftUI

struct OnboardingAccountStep: View {
    @Bindable var vm: OnboardingViewModel

    // EditableHeroSection takes a Binding<IconSource?>; bridge to the non-optional draft.
    @State private var iconSource: IconSource? = nil
    // EditableHeroSection's balance binding is a formatted string.
    @State private var balanceText: String = ""

    private static let heroConfig = HeroConfig(showBalance: true, showCurrency: false)

    var body: some View {
        OnboardingPageContainer(
            progressStep: 2,
            title: String(localized: "onboarding.account.title"),
            subtitle: String(localized: "onboarding.account.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: vm.canAdvanceFromAccountStep,
            onPrimaryTap: {
                Task { await vm.advanceToCategoriesStep() }
            },
            onSkip: {
                Task { await vm.skip() }
            }
        ) {
            ScrollView {
                EditableHeroSection(
                    iconSource: $iconSource,
                    title: $vm.draftAccount.name,
                    balance: $balanceText,
                    currency: .constant(vm.draftCurrency),
                    titlePlaceholder: String(localized: "account.namePlaceholder"),
                    config: Self.heroConfig,
                    autoFocusTitle: true
                )
                .padding(.top, AppSpacing.md)
            }
        }
        .onAppear {
            iconSource = vm.draftAccount.iconSource
            balanceText = vm.draftAccount.balance == 0
                ? ""
                : AmountInputFormatting.bindingString(for: vm.draftAccount.balance)
        }
        .onChange(of: iconSource) { _, newSource in
            if let source = newSource {
                vm.draftAccount.iconSource = source
            }
        }
        .onChange(of: balanceText) { _, newValue in
            let cleaned = AmountInputFormatting.cleanAmountString(newValue)
            vm.draftAccount.balance = Double(cleaned) ?? 0
        }
    }
}

#Preview("Onboarding — Account") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingAccountStep(vm: vm)
    }
}
