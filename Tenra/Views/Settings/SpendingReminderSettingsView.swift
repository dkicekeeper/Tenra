//
//  SpendingReminderSettingsView.swift
//  Tenra
//
//  Settings → Spending reminder (docs/plan-spending-reminder.md §3.6): Ten's evening reminder on
//  days nothing was recorded, its switch and its time. Turning it on asks for notification
//  permission when needed; a denied permission shows the "open iOS Settings" row, as the
//  insight signals' page does.
//

import SwiftUI

struct SpendingReminderSettingsView: View {
    @AppStorage(SpendingReminder.enabledKey) private var isOn = false
    @AppStorage(SpendingReminder.minutesKey) private var minutes = SpendingReminder.defaultMinutes
    @State private var permissionManager = NotificationPermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                FormSection(footer: String(localized: "settings.spendingReminder.footer")) {
                    UniversalRow(
                        String(localized: "settings.spendingReminder.toggle"),
                        icon: "bell",
                        accessory: .toggle(enabledBinding)
                    )
                    if isOn {
                        UniversalRow(
                            String(localized: "settings.spendingReminder.time"),
                            icon: "clock",
                            accessory: .date(timeBinding, components: .hourAndMinute)
                        )
                    }
                }

                if isOn, permissionManager.authorizationStatus == .denied {
                    FormSection {
                        UniversalRow(
                            String(localized: "settings.insightSignals.permissionDenied"),
                            icon: "bell.slash",
                            accessory: .action({ permissionManager.openAppSettings() })
                        )
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
            .animation(AppAnimation.contentSpring, value: isOn)
        }
        .navigationTitle(String(localized: "settings.spendingReminder.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissionManager.checkAuthorizationStatus()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                isOn = on
                Task {
                    await SpendingReminder.setEnabled(on)
                    await permissionManager.checkAuthorizationStatus()
                }
            }
        )
    }

    /// The reminder's time as today's date at that hour, for the system's time picker.
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let time = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
                SpendingReminder.requestReschedule()
            }
        )
    }
}

#Preview {
    NavigationStack {
        SpendingReminderSettingsView()
    }
}
