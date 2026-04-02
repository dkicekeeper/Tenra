//
//  NotificationDebugView.swift
//  AIFinanceManager
//
//  Created on 2026-02-14
//  Purpose: Debug utility for testing notification system
//

import SwiftUI
import UserNotifications

#if DEBUG
struct NotificationDebugView: View {
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingNotifications: [UNNotificationRequest] = []
    @State private var isLoading = false
    @State private var testMessage: String = ""

    var body: some View {
        NavigationStack {
            List {
                // Authorization Status
                Section("Permission Status") {
                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }

                    Button("Request Permission") {
                        Task {
                            await requestPermission()
                        }
                    }
                    .disabled(authStatus == .authorized)

                    Button("Open Settings") {
                        NotificationPermissionManager.shared.openAppSettings()
                    }
                }

                // Pending Notifications
                Section("Pending Notifications (\(pendingNotifications.count))") {
                    if pendingNotifications.isEmpty {
                        Text("No pending notifications")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingNotifications, id: \.identifier) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.content.title)
                                    .font(AppTypography.bodyEmphasis)
                                Text(request.content.body)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                                    if let nextDate = trigger.nextTriggerDate() {
                                        Text("📅 \(formatDate(nextDate))")
                                            .font(AppTypography.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }

                    Button("Refresh") {
                        Task {
                            await loadPendingNotifications()
                        }
                    }
                }

                // Test Actions
                Section("Test Actions") {
                    Button("Schedule Test Notification (5 sec)") {
                        Task {
                            await scheduleTestNotification()
                        }
                    }

                    Button("Cancel All Notifications") {
                        cancelAllNotifications()
                    }
                    .foregroundStyle(.red)
                }

                // Test Message
                if !testMessage.isEmpty {
                    Section("Last Action") {
                        Text(testMessage)
                            .font(AppTypography.caption)
                    }
                }
            }
            .navigationTitle("Notification Debug")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await checkStatus()
                await loadPendingNotifications()
            }
        }
    }

    private var statusText: String {
        switch authStatus {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var statusColor: Color {
        switch authStatus {
        case .authorized, .provisional: return .green
        case .denied: return .red
        default: return .orange
        }
    }

    private func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    private func requestPermission() async {
        let granted = await NotificationPermissionManager.shared.requestAuthorization()
        testMessage = granted ? "✅ Permission granted" : "❌ Permission denied"
        await checkStatus()
    }

    private func loadPendingNotifications() async {
        pendingNotifications = await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    private func scheduleTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "🧪 Test Notification"
        content.body = "This is a test notification scheduled for 5 seconds from now"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            testMessage = "✅ Test notification scheduled for 5 seconds"
            await loadPendingNotifications()
        } catch {
            testMessage = "❌ Failed to schedule: \(error.localizedDescription)"
        }
    }

    private func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        testMessage = "🗑️ All notifications cancelled"
        Task {
            await loadPendingNotifications()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NotificationDebugView()
}
#endif
