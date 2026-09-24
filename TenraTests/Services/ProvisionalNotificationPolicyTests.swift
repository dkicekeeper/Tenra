//
//  ProvisionalNotificationPolicyTests.swift
//  TenraTests
//
//  Pins when Tenra asks iOS for provisional (quiet) notification authorization:
//  only while the user has not decided, and only if the weekly digest or insight
//  signals are on. Both default ON but used to be silently undeliverable.
//

import Testing
import UserNotifications
@testable import Tenra

struct ProvisionalNotificationPolicyTests {

    private func policy(_ status: UNAuthorizationStatus, signals: Bool = true, digest: Bool = true) -> Bool {
        NotificationPermissionManager.shouldRequestProvisional(status: status, signalsEnabled: signals, digestEnabled: digest)
    }

    @Test func undecidedWithSignalsOnRequests() {
        #expect(policy(.notDetermined, signals: true, digest: false))
    }

    @Test func undecidedWithOnlyDigestOnRequests() {
        #expect(policy(.notDetermined, signals: false, digest: true))
    }

    @Test func undecidedWithEverythingOffDoesNotRequest() {
        #expect(!policy(.notDetermined, signals: false, digest: false))
    }

    @Test func decidedStatusesNeverRequest() {
        #expect(!policy(.denied))
        #expect(!policy(.authorized))
        #expect(!policy(.provisional))
    }
}
