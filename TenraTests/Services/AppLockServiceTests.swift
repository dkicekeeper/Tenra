//
//  AppLockServiceTests.swift
//  TenraTests
//
//  Pins the app-lock state machine: when the app locks (cold launch, >= 60 s in
//  the background), when it does not (short absence, the Face ID sheet itself
//  returning the app to .active), and that the lock can only be enabled after a
//  successful authentication.
//

import Testing
import Foundation
import SwiftUI
@testable import Tenra

@MainActor
struct AppLockServiceTests {

    // MARK: - Harness

    private final class Clock {
        var current = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    }

    private final class FakeAuthenticator: AppLockAuthenticating {
        var result: Bool
        var available = true
        var callCount = 0
        init(result: Bool) { self.result = result }
        func biometry() -> AppLockBiometry { available ? .faceID : .unavailable }
        func authenticate(reason: String) async -> Bool {
            callCount += 1
            return result
        }
    }

    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppLockServiceTests.\(UUID().uuidString)")!
    }

    private static func makeService(
        defaults: UserDefaults? = nil,
        clock: Clock? = nil,
        auth: FakeAuthenticator? = nil
    ) -> AppLockService {
        let clock = clock ?? Clock()
        return AppLockService(
            defaults: defaults ?? freshDefaults(),
            now: { clock.current },
            authenticator: auth ?? FakeAuthenticator(result: true)
        )
    }

    /// Enabled and currently unlocked, as after the user turns the lock on in Settings.
    private static func enabledUnlocked(clock: Clock, auth: FakeAuthenticator) async -> AppLockService {
        let service = makeService(clock: clock, auth: auth)
        let applied = await service.setEnabled(true)
        #expect(applied)
        return service
    }

    // MARK: - Pure rule

    @Test func shouldLockPureRule() {
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(!AppLockService.shouldLock(isEnabled: false, backgroundedAt: t0, now: t0.addingTimeInterval(600)))
        #expect(!AppLockService.shouldLock(isEnabled: true, backgroundedAt: nil, now: t0))
        #expect(!AppLockService.shouldLock(isEnabled: true, backgroundedAt: t0, now: t0.addingTimeInterval(59)))
        #expect(AppLockService.shouldLock(isEnabled: true, backgroundedAt: t0, now: t0.addingTimeInterval(60)))
    }

    // MARK: - Cold launch

    @Test func coldLaunchWithLockEnabledStartsLocked() {
        let defaults = Self.freshDefaults()
        defaults.set(true, forKey: "appLock.enabled")
        let service = Self.makeService(defaults: defaults)
        #expect(service.isEnabled)
        #expect(service.isLocked)
    }

    @Test func coldLaunchWithoutLockStartsUnlocked() {
        let service = Self.makeService()
        #expect(!service.isEnabled)
        #expect(!service.isLocked)
    }

    // MARK: - Relock after background

    @Test func shortAbsenceDoesNotLock() async {
        let clock = Clock()
        let service = await Self.enabledUnlocked(clock: clock, auth: FakeAuthenticator(result: true))
        service.handleScenePhase(.background)
        clock.advance(30)
        service.handleScenePhase(.active)
        #expect(!service.isLocked)
    }

    @Test func longAbsenceLocks() async {
        let clock = Clock()
        let service = await Self.enabledUnlocked(clock: clock, auth: FakeAuthenticator(result: true))
        service.handleScenePhase(.background)
        clock.advance(61)
        service.handleScenePhase(.active)
        #expect(service.isLocked)
    }

    // MARK: - Unlock

    @Test func unlockSuccessUnlocks() async {
        let defaults = Self.freshDefaults()
        defaults.set(true, forKey: "appLock.enabled")
        let service = Self.makeService(defaults: defaults, auth: FakeAuthenticator(result: true))
        await service.unlock()
        #expect(!service.isLocked)
    }

    @Test func unlockFailureStaysLocked() async {
        let defaults = Self.freshDefaults()
        defaults.set(true, forKey: "appLock.enabled")
        let service = Self.makeService(defaults: defaults, auth: FakeAuthenticator(result: false))
        await service.unlock()
        #expect(service.isLocked)
    }

    @Test func removedDevicePasscodeNeverLocksTheUserOut() async {
        let defaults = Self.freshDefaults()
        defaults.set(true, forKey: "appLock.enabled")
        let auth = FakeAuthenticator(result: false)
        auth.available = false
        let service = Self.makeService(defaults: defaults, auth: auth)
        #expect(service.isLocked)

        await service.unlock()
        #expect(!service.isLocked)
        #expect(!service.isEnabled)
        #expect(auth.callCount == 0)
    }

    @Test func faceIDSheetReturningToActiveDoesNotRelock() async {
        let clock = Clock()
        let service = await Self.enabledUnlocked(clock: clock, auth: FakeAuthenticator(result: true))
        service.handleScenePhase(.background)
        clock.advance(120)
        service.handleScenePhase(.active)
        #expect(service.isLocked)

        // The Face ID sheet makes the scene inactive, then active again.
        service.handleScenePhase(.inactive)
        service.handleScenePhase(.active)
        await service.unlock()
        #expect(!service.isLocked)

        clock.advance(300)
        service.handleScenePhase(.active)
        #expect(!service.isLocked)
    }

    // MARK: - Settings toggle

    @Test func enablingRequiresSuccessfulAuthentication() async {
        let service = Self.makeService(auth: FakeAuthenticator(result: false))
        let applied = await service.setEnabled(true)
        #expect(!applied)
        #expect(!service.isEnabled)
    }

    @Test func disablingClearsTheLock() async {
        let defaults = Self.freshDefaults()
        defaults.set(true, forKey: "appLock.enabled")
        let service = Self.makeService(defaults: defaults)
        #expect(service.isLocked)
        await service.setEnabled(false)
        #expect(!service.isLocked)
        #expect(!service.isEnabled)
    }

    @Test func enabledStatePersists() async {
        let defaults = Self.freshDefaults()
        let first = Self.makeService(defaults: defaults, auth: FakeAuthenticator(result: true))
        await first.setEnabled(true)

        let relaunched = Self.makeService(defaults: defaults)
        #expect(relaunched.isEnabled)
        #expect(relaunched.isLocked)
    }

    // MARK: - App-switcher cover

    @Test func inactiveSceneIsObscuredOnlyWhenEnabled() async {
        let clock = Clock()
        let enabled = await Self.enabledUnlocked(clock: clock, auth: FakeAuthenticator(result: true))
        enabled.handleScenePhase(.inactive)
        #expect(enabled.isSceneObscured)
        #expect(enabled.shouldShowOverlay)
        enabled.handleScenePhase(.active)
        #expect(!enabled.isSceneObscured)
        #expect(!enabled.shouldShowOverlay)

        let disabled = Self.makeService()
        disabled.handleScenePhase(.inactive)
        #expect(!disabled.isSceneObscured)
        #expect(!disabled.shouldShowOverlay)
    }
}
