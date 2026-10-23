//
//  OnboardingAutoCaptureStepTests.swift
//  TenraTests
//
//  The categories step goes on to "Let Tenra log it for you" (step 4), which finishes
//  onboarding; its statement row is a toggle: a second tap clears it.
//

import Testing
@testable import Tenra

@MainActor
struct OnboardingAutoCaptureStepTests {

    @Test func theCategoriesStepGoesOnToAutoCapture() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.path = [.currency, .account, .categories]
        vm.advanceToAutoCaptureStep()
        #expect(vm.path == [.currency, .account, .categories, .autoCapture])
        // Four steps in the indicator: Tenra's three and auto-capture.
        #expect(OnboardingViewModel.stepSymbols.count == 4)
    }

    @Test func theStatementFollowUpTogglesOnAndOff() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.afterFinish == nil)
        vm.toggleAfterFinish(.statement)
        #expect(vm.afterFinish == .statement)
        vm.toggleAfterFinish(.statement)
        #expect(vm.afterFinish == nil)
    }
}
