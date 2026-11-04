//
//  SpendingReminderOfferCard.swift
//  Tenra
//
//  Ten's offer of the evening reminder (docs/plan-spending-reminder.md §3.5): an adapter over
//  DesignKit's NoticeCard with Ten on the left, as Ten's messages on Home. Shown once there is a
//  record, where it was made: on Home (ContentView.setupCards) and in Ten's chat
//  (AssistantChatView). "Remind me" turns the reminder on and asks for permission; ✕ means
//  not now, and Ten does not ask again.
//

import SwiftUI

struct SpendingReminderOfferCard: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @AppStorage(SpendingReminder.minutesKey) private var minutes = SpendingReminder.defaultMinutes

    var body: some View {
        NoticeCard(
            title: String(localized: "spendingReminder.offer.title"),
            message: String(format: String(localized: "spendingReminder.offer.message"), time),
            actionTitle: String(localized: "spendingReminder.offer.action"),
            actionSystemImage: "bell",
            action: onAccept,
            hideLabel: String(localized: "assistant.notice.hide"),
            onHide: onDecline
        ) {
            ParticleCreature(mood: .happy, style: .compact)
                .frame(width: NoticeCardMetrics.leadingSize, height: NoticeCardMetrics.leadingSize)
                .accessibilityHidden(true)
        }
    }

    /// The reminder's time in the phone's format (20:00, 8:00 PM).
    private var time: String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    SpendingReminderOfferCard(onAccept: {}, onDecline: {})
        .screenPadding()
}
