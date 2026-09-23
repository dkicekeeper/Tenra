//
//  AppLockService.swift
//  Tenra
//
//  Optional app lock (Face ID / Touch ID / device passcode). OFF by default.
//
//  When enabled, the app starts locked and locks again after it has been in the
//  background for `gracePeriod` or longer. While the scene is not active the
//  screen is covered, so the app-switcher snapshot shows no amounts.
//
//  The lock is drawn by `AppLockWindowPresenter` in its own UIWindow above
//  everything else. A view inside the app's SwiftUI hierarchy would sit BELOW
//  any sheet MainTabView has presented (e.g. the add-transaction modal), so an
//  open sheet would stay readable behind a "locked" screen.
//
//  Background work (App Intents run headless, BGAppRefresh) never reaches
//  `.active`, so it is unaffected by the lock.
//

import Foundation
import LocalAuthentication
import Observation
import SwiftUI

// MARK: - Authentication seam

enum AppLockBiometry: Equatable {
    case faceID
    case touchID
    case passcodeOnly
    /// No device passcode is set, so `.deviceOwnerAuthentication` cannot run.
    case unavailable
}

protocol AppLockAuthenticating {
    /// What the device can do right now.
    func biometry() -> AppLockBiometry
    /// Face ID / Touch ID with automatic passcode fallback. False on cancel or failure.
    func authenticate(reason: String) async -> Bool
}

/// `.deviceOwnerAuthentication`, not `...WithBiometrics`: a user whose Face ID
/// fails must still be able to get in with the device passcode.
struct LocalAppLockAuthenticator: AppLockAuthenticating {
    func biometry() -> AppLockBiometry {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcodeOnly
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

// MARK: - AppLockService

@MainActor
@Observable
final class AppLockService {

    static let shared = AppLockService()

    nonisolated static let gracePeriod: TimeInterval = 60
    private static let enabledKey = "appLock.enabled"

    /// Pure relock rule, pinned by `AppLockServiceTests`.
    nonisolated static func shouldLock(isEnabled: Bool, backgroundedAt: Date?, now: Date) -> Bool {
        guard isEnabled, let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= gracePeriod
    }

    // MARK: Dependencies

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored let authenticator: AppLockAuthenticating

    /// Wired once in `TenraApp.init` to `AppLockWindowPresenter`. Tests leave it nil.
    @ObservationIgnored var onOverlayVisibilityChange: ((Bool) -> Void)?

    // MARK: State

    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var isAuthenticating = false

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                isLocked = false
                isSceneObscured = false
            }
        }
    }

    private(set) var isLocked: Bool {
        didSet { notifyOverlay() }
    }

    /// Covers the screen while the scene is inactive / in the background.
    private(set) var isSceneObscured = false {
        didSet { notifyOverlay() }
    }

    var shouldShowOverlay: Bool { isLocked || isSceneObscured }

    // MARK: Init

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        authenticator: AppLockAuthenticating = LocalAppLockAuthenticator()
    ) {
        self.defaults = defaults
        self.now = now
        self.authenticator = authenticator
        let enabled = defaults.bool(forKey: Self.enabledKey)
        self.isEnabled = enabled
        // Cold launch starts locked when the lock is on.
        self.isLocked = enabled
    }

    // MARK: Scene lifecycle

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = now()
            isSceneObscured = isEnabled
        case .inactive:
            // Also fires under the Face ID sheet itself; harmless, the lock is
            // on screen at that moment anyway.
            isSceneObscured = isEnabled
        case .active:
            isSceneObscured = false
            if Self.shouldLock(isEnabled: isEnabled, backgroundedAt: backgroundedAt, now: now()) {
                isLocked = true
            }
            // Cleared on every activation: the Face ID sheet returns the app to
            // `.active` without a new `.background`, and must not re-lock it.
            backgroundedAt = nil
            if isLocked {
                Task { await unlock() }
            }
        @unknown default:
            break
        }
    }

    // MARK: Unlock

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        // The device passcode was removed after the lock was enabled: nothing
        // can authenticate any more, and staying locked would shut the user out
        // of their own data for good. The lock cannot protect anything without
        // a passcode, so turn it off.
        guard authenticator.biometry() != .unavailable else {
            isEnabled = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: String(localized: "appLock.reason")) {
            isLocked = false
        }
    }

    // MARK: Settings

    /// Turning the lock ON requires one successful authentication first, so a
    /// user can never enable a lock they cannot open. Turning it OFF is immediate.
    /// Returns whether the requested state was applied.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            isEnabled = false
            return true
        }
        guard !isEnabled else { return true }
        guard await authenticator.authenticate(reason: String(localized: "appLock.reason")) else {
            return false
        }
        isEnabled = true
        return true
    }

    // MARK: Private

    private func notifyOverlay() {
        onOverlayVisibilityChange?(shouldShowOverlay)
    }
}
