//
//  SpendingReminderTests.swift
//  TenraTests
//
//  Pins the reminder's state (docs/plan-spending-reminder.md §3.2, §3.5): offered once after the
//  first record and never after a "not now", not offered once it is on, off at 20:00 by
//  default, and a record made in the background (auto-capture) marks the day recorded without
//  counting as the person coming back.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct SpendingReminderTests {

    private func freshDefaults(_ name: String = UUID().uuidString) -> (UserDefaults, String) {
        let suite = "SpendingReminderTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func transaction(createdAt: Date, series: String? = nil) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: "2026-11-05", description: "", amount: 1500, currency: "KZT",
            type: .expense, category: "Кафе", recurringSeriesId: series,
            createdAt: createdAt.timeIntervalSince1970
        )
    }

    @Test("Off at 20:00 and not asked yet by default")
    func defaultsAreOffAt20() {
        let (defaults, _) = freshDefaults()
        #expect(!SpendingReminder.isEnabled(defaults: defaults))
        #expect(SpendingReminder.minutes(defaults: defaults) == 1200)
        #expect(SpendingReminder.offerState(defaults: defaults) == .notAsked)
    }

    @Test("Offered once there is a record, and never again after \"not now\"")
    func offeredOnceAfterFirstRecord() {
        let (defaults, suite) = freshDefaults()
        #expect(!SpendingReminder.shouldOffer(hasRecords: false, defaults: defaults))
        #expect(SpendingReminder.shouldOffer(hasRecords: true, defaults: defaults))
        SpendingReminder.declineOffer(defaults: defaults)
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, defaults: defaults))
        let reopened = UserDefaults(suiteName: suite)!
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, defaults: reopened))
    }

    @Test("Not offered while the reminder is on")
    func enabledHidesOffer() {
        let (defaults, _) = freshDefaults()
        defaults.set(true, forKey: SpendingReminder.enabledKey)
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, defaults: defaults))
    }

    @Test("A background record marks the day without counting as a reaction")
    func backgroundRecordKeepsReaction() {
        let (defaults, _) = freshDefaults()
        let reaction = Date(timeIntervalSince1970: 1_793_500_000)
        let later = reaction.addingTimeInterval(4 * 86_400)
        SpendingReminder.noteAppOpened(now: reaction, defaults: defaults)
        SpendingReminder.noteRecorded([transaction(createdAt: later)], now: later, defaults: defaults)
        #expect(SpendingReminder.lastReaction(defaults: defaults) == reaction)
        #expect(SpendingReminder.lastRecorded(defaults: defaults) == later)
    }

    @Test("Creating a recurring payment is the person recording today")
    func seriesCreatedIsARecord() {
        let (defaults, _) = freshDefaults()
        let now = Date(timeIntervalSince1970: 1_793_500_000)
        SpendingReminder.noteSeriesCreated(now: now, defaults: defaults)
        #expect(SpendingReminder.lastRecorded(defaults: defaults) == now)
    }

    @Test("An occurrence of a recurring series is not the person recording")
    func recurringRecordIgnored() {
        let (defaults, _) = freshDefaults()
        let now = Date(timeIntervalSince1970: 1_793_500_000)
        SpendingReminder.noteRecorded([transaction(createdAt: now, series: "s1")], now: now, defaults: defaults)
        #expect(SpendingReminder.lastRecorded(defaults: defaults) == nil)
    }

    @Test("The cards' rule over the stored values is the service's")
    func offerRuleOverStoredValues() {
        #expect(SpendingReminder.shouldOffer(hasRecords: true, offer: nil, enabled: false))
        #expect(SpendingReminder.shouldOffer(hasRecords: true, offer: "notAsked", enabled: false))
        #expect(!SpendingReminder.shouldOffer(hasRecords: false, offer: nil, enabled: false))
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, offer: "declined", enabled: false))
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, offer: "accepted", enabled: false))
        #expect(!SpendingReminder.shouldOffer(hasRecords: true, offer: nil, enabled: true))
    }
}
