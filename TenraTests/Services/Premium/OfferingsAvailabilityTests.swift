//
//  OfferingsAvailabilityTests.swift
//  TenraTests
//
//  Pins when the paywall shows RevenueCatUI and when it shows the "temporarily unavailable"
//  state instead. The prod failure this guards: RevenueCat error 23 (the App Store returned no
//  products) made RevenueCatUI show its raw alert, whose OK closed the sheet.
//

import Testing
@testable import Tenra

struct OfferingsAvailabilityTests {

    @Test("A current offering with packages can be sold")
    func packagesCanSell() {
        let availability = OfferingsAvailability.loaded(currentPackageCount: 3)
        #expect(availability == .available(packageCount: 3))
        #expect(availability.canSell)
    }

    @Test("No current offering, or an empty one, has nothing to sell")
    func emptyOffering() {
        #expect(OfferingsAvailability.loaded(currentPackageCount: nil) == .nothingToSell(revenueCatCode: nil))
        #expect(OfferingsAvailability.loaded(currentPackageCount: 0) == .nothingToSell(revenueCatCode: nil))
        #expect(!OfferingsAvailability.loaded(currentPackageCount: 0).canSell)
    }

    @Test("RevenueCat error 23 (no products from the App Store) has nothing to sell")
    func configurationError() {
        let availability = OfferingsAvailability.failure(revenueCatCode: 23)
        #expect(availability == .nothingToSell(revenueCatCode: 23))
        #expect(!availability.canSell)
    }

    @Test("Network errors are offline", arguments: [10, 32, 35])
    func offline(code: Int) {
        #expect(OfferingsAvailability.failure(revenueCatCode: code) == .offline)
    }

    @Test("Any other error is a failure, with its code when it has one")
    func otherFailures() {
        #expect(OfferingsAvailability.failure(revenueCatCode: 2) == .failed(revenueCatCode: 2))
        #expect(OfferingsAvailability.failure(revenueCatCode: nil) == .failed(revenueCatCode: nil))
        #expect(!OfferingsAvailability.notConfigured.canSell)
    }
}
