//
//  PaywallPlacementTests.swift
//  TenraTests
//
//  Pins the RevenueCat placement identifiers of the paywall's gates. They are set up by hand
//  in the RevenueCat dashboard (Placements, docs/promotion-plan.md §2) and double as the
//  `paywall_source` attribute: a renamed case would silently fall back to the current offering
//  and split the attribute's history.
//

import Testing
@testable import Tenra

@MainActor
struct PaywallPlacementTests {

    @Test("Every gate's placement is its paywall_source")
    func placementIsSource() {
        for source in PaywallSource.allCases {
            #expect(source.placementID == source.rawValue)
        }
    }

    @Test("The placement identifiers the dashboard is set up with")
    func identifiers() {
        let ids = PaywallSource.allCases.map(\.placementID)
        #expect(ids == [
            "account_add", "deposit_add", "loan_add", "debt_add", "asset_add", "asset_estimate",
            "voice", "import", "assistant", "assistant_attachment", "insights", "settings",
            "onboarding",
        ])
        #expect(Set(ids).count == ids.count)
    }
}
