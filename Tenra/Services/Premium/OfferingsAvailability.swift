//
//  OfferingsAvailability.swift
//  Tenra
//
//  Whether the paywall has something to sell, as plain values: the paywall sheet and the
//  launch health check read it without RevenueCat (PremiumManager is the only file that
//  imports the SDK and turns its offerings or error into one of these).
//

import Foundation

nonisolated enum OfferingsAvailability: Equatable, Sendable {
    /// The current offering has packages: RevenueCatUI's paywall can be shown.
    case available(packageCount: Int)
    /// RevenueCat is not configured in this build (no API key), so nothing can be bought.
    case notConfigured
    /// The App Store returned no products: no current offering, an empty one, or RevenueCat's
    /// configuration error (23), which is what a missing Paid Apps agreement produces.
    case nothingToSell(revenueCatCode: Int?)
    /// No connection (or the App Store timed out): nothing is known about the products.
    case offline
    /// Any other RevenueCat error.
    case failed(revenueCatCode: Int?)

    var canSell: Bool {
        if case .available = self { return true }
        return false
    }

    /// RevenueCat `ErrorCode` raw values told apart here
    /// (purchases-ios, Sources/Error Handling/ErrorCode.swift).
    enum RevenueCatCode {
        static let network = 10
        static let configuration = 23
        static let productRequestTimedOut = 32
        static let offlineConnection = 35
    }

    /// From a successful offerings fetch: `currentPackageCount` is nil without a current offering.
    static func loaded(currentPackageCount: Int?) -> OfferingsAvailability {
        guard let count = currentPackageCount, count > 0 else {
            return .nothingToSell(revenueCatCode: nil)
        }
        return .available(packageCount: count)
    }

    /// From a failed fetch: `revenueCatCode` is nil when the error was not a RevenueCat one.
    static func failure(revenueCatCode: Int?) -> OfferingsAvailability {
        switch revenueCatCode {
        case RevenueCatCode.configuration:
            return .nothingToSell(revenueCatCode: revenueCatCode)
        case RevenueCatCode.network, RevenueCatCode.offlineConnection, RevenueCatCode.productRequestTimedOut:
            return .offline
        default:
            return .failed(revenueCatCode: revenueCatCode)
        }
    }
}
