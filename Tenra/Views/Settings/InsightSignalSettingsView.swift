//
//  InsightSignalSettingsView.swift
//  Tenra
//
//  Insights product audit 2026-07 — Phase C.
//  Master switch + per-kind toggles for insight signal notifications.
//  Enabling the master switch requests notification permission when needed;
//  a denied permission shows an "open iOS Settings" row instead of the toggles
//  silently doing nothing.
//

import SwiftUI

struct InsightSignalSettingsView: View {
    @State private var settings = InsightSignalSettings.shared
    @State private var permissionManager = NotificationPermissionManager.shared

    var body: some View {
        // DesignKit 8.0.0: glass sections of rows (a List of system toggles before).
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                FormSection(footer: String(localized: "settings.insightSignals.footer")) {
                    UniversalRow(String(localized: "settings.insightSignals.master"), icon: "bell.badge",
                                 accessory: .toggle(masterBinding))
                }

                if settings.isEnabled {
                    if permissionManager.authorizationStatus == .denied {
                        FormSection {
                            UniversalRow(
                                String(localized: "settings.insightSignals.permissionDenied"),
                                icon: "bell.slash",
                                accessory: .action({ permissionManager.openAppSettings() })
                            )
                        }
                    }

                    FormSection {
                        ForEach(InsightSignalKind.allCases, id: \.rawValue) { kind in
                            UniversalRow(kind.displayName, accessory: .toggle(kindBinding(kind)))
                        }
                    }

                    FormSection {
                        UniversalRow(String(localized: "settings.insightSignals.weeklyDigest"), icon: "calendar",
                                     accessory: .toggle(digestBinding))
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
            .animation(AppAnimation.contentSpring, value: settings.isEnabled)
        }
        .navigationTitle(String(localized: "settings.insightSignals.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissionManager.checkAuthorizationStatus()
        }
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                settings.isEnabled = newValue
                if newValue {
                    Task { await permissionManager.requestAuthorization() }
                }
            }
        )
    }

    private func kindBinding(_ kind: InsightSignalKind) -> Binding<Bool> {
        Binding(
            get: { settings.isKindEnabled(kind) },
            set: { settings.setKind(kind, enabled: $0) }
        )
    }

    private var digestBinding: Binding<Bool> {
        Binding(
            get: { settings.weeklyDigestEnabled },
            set: { newValue in
                settings.weeklyDigestEnabled = newValue
                // Turning the digest off removes the already-pending Monday push;
                // turning it on re-arms on the next insights recompute.
                if !newValue {
                    WeeklyDigestScheduler.shared.cancel()
                }
            }
        )
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        InsightSignalSettingsView()
    }
}
