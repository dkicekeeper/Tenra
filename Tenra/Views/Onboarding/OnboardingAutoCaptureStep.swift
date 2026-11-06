//
//  OnboardingAutoCaptureStep.swift
//  Tenra
//
//  Step 4: "Let Tenra log it for you". What fills Tenra without typing, each optional: the
//  Wallet automation for Apple Pay and, on iOS 27, the bank notification automation (their
//  step-by-step guides, in a sheet), and a bank statement read right after onboarding (Ten where it runs, else the import
//  tab). The primary button and ✕ both finish onboarding with what was collected: setting up
//  the automations can wait (Home keeps a card for it, AutoCaptureSetupCard). Then, to a free
//  person when the App Store has something to sell, Tenra Pro's paywall with its trial; Home
//  comes once it closes.
//

import SwiftUI

struct OnboardingAutoCaptureStep: View {
    @Bindable var vm: OnboardingViewModel
    /// The bank notification row: iOS 27 with its setup guide in the build.
    var showsBankNotifications = OnboardingViewModel.offersBankNotifications


    var body: some View {
        OnboardingPageContainer(
            progressStep: 4,
            title: String(localized: "onboarding.autoCapture.title"),
            subtitle: String(localized: "onboarding.autoCapture.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.start"),
            primaryButtonEnabled: !vm.isFinishing,
            onPrimaryTap: {
                Task { await vm.finish() }
            },
            onSkip: {
                Task { await vm.finish() }
            },
            stepSymbols: OnboardingViewModel.stepSymbols
        ) {
            ScrollView {
                FormSection {
                    // A guide to open is a row with a chevron (`.navigation`, DesignKit's rule);
                    // the statement is a choice for after the start, so a switch.
                    UniversalRow(
                        String(localized: "onboarding.autoCapture.applePay.title"),
                        icon: "wave.3.right",
                        hint: String(localized: "onboarding.autoCapture.applePay.hint"),
                        accessory: .navigation { WalletSetupGuideView() }
                    )
                    if showsBankNotifications {
                        UniversalRow(
                            String(localized: "onboarding.autoCapture.notifications.title"),
                            icon: "bell.badge",
                            hint: String(localized: "onboarding.autoCapture.notifications.hint"),
                            accessory: .navigation { BankNotificationGuideView() }
                        )
                    }
                    UniversalRow(
                        String(localized: "onboarding.autoCapture.statement.title"),
                        icon: "doc.text.viewfinder",
                        hint: String(localized: "onboarding.autoCapture.statement.hint"),
                        accessory: .toggle(statementAfterStart)
                    )
                }
                // The onboarding stack centres its text; rows read from the leading edge.
                .multilineTextAlignment(.leading)
                .screenPadding()
                .padding(.top, AppSpacing.md)
            }
        }
        // The trial offer once "Start" saved everything (OnboardingViewModel.finish); closing it,
        // or a purchase, ends onboarding.
        .paywallSheet(isPresented: $vm.showingTrialOffer, source: .onboarding)
        .onChange(of: vm.showingTrialOffer) { _, showing in
            if showing {
                PremiumManager.shared.markOnboardingOfferShown()
            } else {
                vm.trialOfferClosed()
            }
        }
    }

    /// On: after "Start", Ten (or the import tab) opens with a statement to pick.
    private var statementAfterStart: Binding<Bool> {
        Binding(
            get: { vm.afterFinish == .statement },
            set: { _ in vm.toggleAfterFinish(.statement) }
        )
    }
}

#Preview("Onboarding — Auto-capture") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingAutoCaptureStep(vm: vm)
    }
}
