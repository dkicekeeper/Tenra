//
//  PremiumManagerAutomatedRunTests.swift
//  TenraTests
//
//  The host app launched for these tests ran `PremiumManager.configure()` in
//  AppDelegate. It must have skipped RevenueCat: every CI Simulator that configured
//  the SDK became a new anonymous customer in the RevenueCat charts.
//

import Testing
@testable import Tenra

@MainActor
struct PremiumManagerAutomatedRunTests {

    @Test("The unit-test host never configures RevenueCat")
    func testHostSkipsRevenueCat() {
        #expect(PremiumManager.shared.isConfigured == false)
        #expect(PremiumManager.shared.appUserID == nil)
    }
}
