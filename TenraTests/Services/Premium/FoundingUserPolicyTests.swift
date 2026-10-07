//
//  FoundingUserPolicyTests.swift
//  TenraTests
//
//  Pins who is a Founding User. The device rule (onboarded before the first Pro build ran)
//  is kept; the App Store rule (first download before the first Pro build went on sale)
//  makes the status survive a reinstall and a new phone; a stored flag is never revoked;
//  TestFlight / sandbox records (placeholder date 2013-08-01) never count.
//

import Foundation
import Testing
@testable import Tenra

struct FoundingUserPolicyTests {

    private let cutoff = PremiumConfig.foundingUserDownloadCutoff

    private func download(_ offset: TimeInterval, production: Bool = true) -> FoundingUserPolicy.OriginalDownload {
        FoundingUserPolicy.OriginalDownload(purchaseDate: cutoff.addingTimeInterval(offset), isProduction: production)
    }

    private func reason(
        stored: Bool = false,
        evaluatedBefore: Bool = true,
        onboarded: Bool = false,
        download: FoundingUserPolicy.OriginalDownload? = nil
    ) -> FoundingUserPolicy.Reason? {
        FoundingUserPolicy.reason(for: FoundingUserPolicy.Inputs(
            storedFlag: stored,
            evaluatedBefore: evaluatedBefore,
            onboardingCompleted: onboarded,
            originalDownload: download
        ))
    }

    @Test("A stored founder flag is never revoked, whatever the App Store says")
    func storedFlagWins() {
        #expect(reason(stored: true, download: download(86_400)) == .alreadyFounder)
        #expect(reason(stored: true, download: download(-86_400, production: false)) == .alreadyFounder)
    }

    @Test("Onboarded before the first Pro-build launch on this device: founder")
    func existingUserAtProLaunch() {
        #expect(reason(evaluatedBefore: false, onboarded: true) == .existingUserAtProLaunch)
    }

    @Test("The device rule applies only on the first evaluation")
    func deviceRuleOnlyOnce() {
        #expect(reason(evaluatedBefore: true, onboarded: true) == nil)
        #expect(reason(evaluatedBefore: false, onboarded: false) == nil)
    }

    @Test("Reinstall or new phone: a production first download before the cutoff is a founder")
    func downloadedBeforePro() {
        #expect(reason(evaluatedBefore: false, onboarded: false, download: download(-1)) == .downloadedBeforePro)
    }

    @Test("A first download at or after the cutoff is not a founder")
    func downloadedAfterPro() {
        #expect(reason(download: download(0)) == nil)
        #expect(reason(download: download(86_400)) == nil)
    }

    @Test("TestFlight and sandbox records never make a founder")
    func sandboxIgnored() {
        let sandbox = FoundingUserPolicy.OriginalDownload(
            purchaseDate: Date(timeIntervalSince1970: 1_375_340_400),  // StoreKit's sandbox placeholder
            isProduction: false
        )
        #expect(reason(download: sandbox) == nil)
        #expect(!FoundingUserPolicy.downloadedBeforePro(sandbox))
    }

    @Test("The cutoff is the end of 2026-07-09 in Kazakhstan (version 1.0.1's release day)")
    func cutoffValue() throws {
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-07-10T00:00:00+05:00"))
        #expect(cutoff == expected)
    }
}
