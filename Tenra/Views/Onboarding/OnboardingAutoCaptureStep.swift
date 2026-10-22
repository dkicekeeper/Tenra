//
//  OnboardingAutoCaptureStep.swift
//  Tenra
//
//  Step 4: "Let Tenra log it for you". What fills Tenra without typing, each optional: the
//  Wallet automation for Apple Pay (its step-by-step guide, in a sheet), bank notifications on
//  iOS 27, and a bank statement read right after onboarding (Ten where it runs, else the import
//  tab). The primary button and ✕ both finish onboarding with what was collected: setting up
//  the automations can wait (Home keeps a card for it, AutoCaptureSetupCard).
//

import SwiftUI

struct OnboardingAutoCaptureStep: View {
    @Bindable var vm: OnboardingViewModel
    /// The bank notification row: iOS 27 with its setup guide in the build.
    var showsBankNotifications = OnboardingViewModel.offersBankNotifications

    @State private var showingWalletGuide = false

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
                    UniversalRow(
                        String(localized: "onboarding.autoCapture.applePay.title"),
                        icon: "wave.3.right",
                        hint: String(localized: "onboarding.autoCapture.applePay.hint"),
                        accessory: .action { showingWalletGuide = true }
                    )
                    if showsBankNotifications {
                        UniversalRow(
                            String(localized: "onboarding.autoCapture.notifications.title"),
                            icon: "bell.badge",
                            value: vm.afterFinish == .bankNotifications ? String(localized: "onboarding.autoCapture.afterStart") : nil,
                            hint: String(localized: "onboarding.autoCapture.notifications.hint"),
                            accessory: .action { vm.toggleAfterFinish(.bankNotifications) }
                        )
                    }
                    UniversalRow(
                        String(localized: "onboarding.autoCapture.statement.title"),
                        icon: "doc.text.viewfinder",
                        value: vm.afterFinish == .statement ? String(localized: "onboarding.autoCapture.afterStart") : nil,
                        hint: String(localized: "onboarding.autoCapture.statement.hint"),
                        accessory: .action { vm.toggleAfterFinish(.statement) }
                    )
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
            }
        }
        .sheet(isPresented: $showingWalletGuide) {
            NavigationStack {
                WalletSetupGuideView()
            }
        }
    }
}

#Preview("Onboarding — Auto-capture") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingAutoCaptureStep(vm: vm)
    }
}
