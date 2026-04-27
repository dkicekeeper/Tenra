//
//  OnboardingViewModelTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct OnboardingViewModelTests {
    @Test func draftCurrencyDefaultsToKZT() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftCurrency == "KZT")
    }

    @Test func draftCategoriesAreAllSelectedByDefault() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftCategories.count == 15)
        #expect(vm.draftCategories.allSatisfy { $0.isSelected })
    }

    @Test func selectedCountReflectsToggles() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.draftCategories[0].isSelected = false
        vm.draftCategories[1].isSelected = false
        #expect(vm.selectedPresetCount == 13)
    }

    @Test func draftAccountStartsEmpty() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftAccount.name == "")
        #expect(vm.draftAccount.balance == 0)
    }

    @Test func canCompleteAccountStepRequiresName() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.canAdvanceFromAccountStep == false)
        vm.draftAccount.name = "Kaspi"
        #expect(vm.canAdvanceFromAccountStep == true)
    }

    @Test func canCompleteCategoriesRequiresAtLeastOneSelected() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.canFinish == true)
        for index in vm.draftCategories.indices {
            vm.draftCategories[index].isSelected = false
        }
        #expect(vm.canFinish == false)
    }
}
