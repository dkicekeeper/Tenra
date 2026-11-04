//
//  SpendingReminderSchedulingTests.swift
//  TenraTests
//
//  Pins what SpendingReminder hands the notification center (docs/plan-spending-reminder.md
//  §3.1, §3.7) through a fake center: nothing while off or without permission, nothing added
//  once switched off mid-reschedule, the series under day-keyed ids, tonight's reminder removed
//  the moment something is recorded (before anything async), Ten drawn once per mood, and the
//  RevenueCat attribute written only when it changes.
//

import Testing
import Foundation
import UserNotifications
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
final class SpendingReminderSchedulingTests {

    final class FakeCenter: SpendingReminderCenter {
        var status: UNAuthorizationStatus = .authorized
        var pending: [String] = []
        var added: [UNNotificationRequest] = []
        var removed: [String] = []
        /// Runs while `reschedule` waits for the status, after it removed the old series.
        var onStatus: (() -> Void)?

        func pendingIdentifiers() async -> [String] { pending }
        func remove(_ identifiers: [String]) {
            removed += identifiers
            pending.removeAll { identifiers.contains($0) }
        }
        func authorizationStatus() async -> UNAuthorizationStatus {
            onStatus?()
            return status
        }
        func add(_ request: UNNotificationRequest) async {
            added.append(request)
            pending.append(request.identifier)
        }
    }

    private let center = FakeCenter()
    private let defaults: UserDefaults
    private var drawn: [String] = []
    private var attributes: [String] = []

    init() {
        let suite = "SpendingReminderSchedulingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        SpendingReminder.center = center
        // Weak: other suites reschedule too once this instance is gone.
        SpendingReminder.drawArt = { [weak self] mood in
            self?.drawn.append("\(mood)")
            return Data([1])
        }
        SpendingReminder.writeAttribute = { [weak self] in self?.attributes.append($0) }
        SpendingReminder.resetArtCache()
    }

    /// 2026-11-05 06:00 UTC: morning from UTC-5 to UTC+13 (the Mac here, CI in UTC).
    private let now = Date(timeIntervalSince1970: 1_793_858_400)

    private func enable() {
        defaults.set(true, forKey: SpendingReminder.enabledKey)
        SpendingReminder.noteAppOpened(now: now, defaults: defaults)
    }

    @Test("Off: nothing is added")
    func disabledSchedulesNothing() async {
        await SpendingReminder.reschedule(now: now, defaults: defaults)
        #expect(center.added.isEmpty)
    }

    @Test("No permission: nothing is added")
    func noPermissionSchedulesNothing() async {
        enable()
        center.status = .denied
        await SpendingReminder.reschedule(now: now, defaults: defaults)
        #expect(center.added.isEmpty)
    }

    @Test("Switched off while a reschedule is under way: nothing is added")
    func switchedOffMidRescheduleAddsNothing() async {
        enable()
        await SpendingReminder.waitUntilIdle()
        center.added = []
        center.onStatus = { [defaults] in defaults.set(false, forKey: SpendingReminder.enabledKey) }
        await SpendingReminder.reschedule(now: now, defaults: defaults)
        #expect(center.added.isEmpty)
    }

    @Test("On: the series goes under one id per day")
    func enabledSchedulesSeriesByDay() async {
        enable()
        await SpendingReminder.waitUntilIdle()
        let ids = center.added.map(\.identifier)
        #expect(ids.count == 7)
        #expect(Set(ids).count == 7)
        #expect(ids.first == SpendingReminder.identifier(for: now))
    }

    @Test("A record removes tonight's reminder before anything async")
    func recordRemovesTonightAtOnce() async {
        enable()
        await SpendingReminder.waitUntilIdle()
        center.removed = []
        let tx = Transaction(
            id: "t1", date: "2026-11-05", description: "", amount: 1500, currency: "KZT",
            type: .expense, category: "Кафе", createdAt: now.timeIntervalSince1970
        )
        SpendingReminder.noteRecorded([tx], now: now, defaults: defaults)
        #expect(center.removed.contains(SpendingReminder.identifier(for: now)))
    }

    @Test("Ten is drawn once per mood, however many reschedules")
    func artDrawnOncePerMood() async {
        enable()
        await SpendingReminder.waitUntilIdle()
        await SpendingReminder.reschedule(now: now, defaults: defaults)
        #expect(drawn.sorted() == ["happy", "idle"])
    }

    @Test("The attribute follows the state and is written only when it changes")
    func attributeWrittenOnChange() async {
        enable()
        await SpendingReminder.waitUntilIdle()
        await SpendingReminder.reschedule(now: now, defaults: defaults)
        center.status = .denied
        await SpendingReminder.reschedule(now: now, defaults: defaults)
        #expect(attributes == ["on", "denied"])
    }

    @Test("The attribute's value for each state")
    func attributeValues() {
        #expect(SpendingReminder.attributeValue(enabled: true, offer: .accepted, status: .authorized) == "on")
        #expect(SpendingReminder.attributeValue(enabled: true, offer: .accepted, status: .provisional) == "on")
        #expect(SpendingReminder.attributeValue(enabled: true, offer: .accepted, status: .denied) == "denied")
        #expect(SpendingReminder.attributeValue(enabled: false, offer: .accepted, status: .authorized) == "off")
        #expect(SpendingReminder.attributeValue(enabled: false, offer: .declined, status: .authorized) == "declined")
        #expect(SpendingReminder.attributeValue(enabled: false, offer: .notAsked, status: .authorized) == nil)
    }
}
