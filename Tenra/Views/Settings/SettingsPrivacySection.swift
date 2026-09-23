//
//  SettingsPrivacySection.swift
//  Tenra
//
//  Opt-in app lock (Face ID / Touch ID / passcode). Enabling requires one
//  successful authentication first (AppLockService.setEnabled), so the toggle
//  simply stays off if the user cancels.
//

import SwiftUI

struct SettingsPrivacySection: View {
    @State private var lock = AppLockService.shared
    @State private var biometry: AppLockBiometry = .unavailable

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { lock.isEnabled },
                set: { newValue in
                    Task { await lock.setEnabled(newValue) }
                }
            )) {
                Label(toggleTitle, systemImage: symbolName)
            }
            .tint(AppColors.accent)
            .disabled(biometry == .unavailable && !lock.isEnabled)
        } header: {
            Text(String(localized: "settings.privacy.header"))
        } footer: {
            Text(String(localized: biometry == .unavailable
                ? "settings.appLock.unavailable"
                : "settings.appLock.footer"))
        }
        .task {
            biometry = lock.authenticator.biometry()
        }
    }

    private var toggleTitle: String {
        switch biometry {
        case .faceID: String(localized: "settings.appLock.faceID")
        case .touchID: String(localized: "settings.appLock.touchID")
        case .passcodeOnly, .unavailable: String(localized: "settings.appLock.passcode")
        }
    }

    private var symbolName: String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .passcodeOnly, .unavailable: "lock"
        }
    }
}

#Preview {
    NavigationStack {
        List {
            SettingsPrivacySection()
        }
    }
}
