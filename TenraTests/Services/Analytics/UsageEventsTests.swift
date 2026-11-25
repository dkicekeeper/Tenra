//
//  UsageEventsTests.swift
//  TenraTests
//
//  The app's usage counts (UsageEvents, docs/plan-sales.md §4): milestones once per install,
//  the return days, the install week, the first day's path, the caps, the switch, the Pro
//  transitions, failed sends, and the wire carrying no identifier. Each test has its own
//  UserDefaults suite and transport; nothing global is touched.
//

import Testing
import Foundation
@testable import Tenra

/// Keeps what it is given; fails the next `failuresLeft` sends.
nonisolated private final class RecordingTransport: UsageEventsTransport, @unchecked Sendable {
    var batches: [[UsageEvent]] = []
    var failuresLeft = 0

    func send(_ events: [UsageEvent]) async throws {
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw URLError(.notConnectedToInternet)
        }
        batches.append(events)
    }
}

@MainActor
struct UsageEventsTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    /// A moment in December 2026 on the phone's clock.
    private func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 12, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
    }

    private func make(_ defaults: UserDefaults, transport: RecordingTransport? = RecordingTransport(),
                      traits: UsageTraits = UsageTraits()) -> UsageEvents {
        UsageEvents(defaults: defaults, isSilent: false, transport: transport, traits: { traits })
    }

    private func names(_ events: [UsageEvent]) -> [String] {
        events.map { $0.value.isEmpty ? $0.name : "\($0.name):\($0.value)" }
    }

    @Test("A milestone goes once per install, also after a relaunch")
    func aMilestoneGoesOnce() {
        let suite = defaults()
        let usage = make(suite)
        usage.reach(.tenOpened, now: at(1))
        usage.reach(.tenOpened, now: at(1))
        #expect(names(usage.pending) == ["installed", "ten_opened"])
        let again = make(suite)
        again.reach(.tenOpened, now: at(2))
        #expect(names(again.pending) == ["installed", "ten_opened"])
    }

    @Test("The first open is the install; the return days and the second week follow")
    func theFirstOpenIsInstalledThenReturnsCount() {
        let usage = make(defaults())
        usage.noteOpen(cold: true, now: at(1, 23, 59))
        usage.noteOpen(cold: false, now: at(2, 0, 1))
        usage.noteOpen(cold: true, now: at(8))
        usage.noteOpen(cold: true, now: at(9))
        let milestones = usage.pending.filter { $0.kind == "m" }
        #expect(names(milestones) == ["installed", "returned:1", "returned:7", "returned:week2"])
        #expect(usage.pending.filter { $0.name == "open" }.count == 4)
        #expect(usage.pending.first { $0.value == "1" && $0.name == "returned" }?.day == 1)
    }

    @Test("The cohort is the install's ISO week")
    func theCohortIsAnISOWeek() {
        #expect(UsageEvents.cohort(installedAt: at(28)) == "2026-W53")
        #expect(UsageEvents.cohort(installedAt: at(4, month: 1, year: 2027)) == "2027-W01")
        #expect(UsageEvents.cohort(installedAt: at(1)) == "2026-W49")
        let usage = make(defaults())
        usage.noteOpen(cold: true, now: at(1))
        usage.noteOpen(cold: true, now: at(9))
        #expect(Set(usage.pending.map(\.cohort)) == ["2026-W49"])
    }

    @Test("furthest0 follows the first day only")
    func furthest0FollowsDayZeroOnly() {
        let usage = make(defaults())
        usage.reach(.onboardingStep(.welcome), now: at(1))
        usage.reach(.onboardingStep(.currency), now: at(1))
        usage.reach(.entries(1), now: at(1))
        usage.reach(.reminderOn, now: at(3))
        #expect(usage.pending.last?.furthest0 == "entry")
        #expect(usage.pending.first { $0.name == "onboarding" && $0.value == "currency" }?.furthest0 == "currency")
    }

    @Test("An event keeps the day it happened, not the day it is sent")
    func eventsCarryTheDayTheyHappened() async {
        let transport = RecordingTransport()
        let usage = make(defaults(), transport: transport)
        usage.reach(.tenOpened, now: at(1))
        usage.count(.entry, now: at(4))
        await usage.flush()
        #expect(transport.batches.first?.map(\.day) == [0, 0, 3])
        #expect(usage.pending.isEmpty)
    }

    @Test("The buffer keeps the 500 newest")
    func theBufferKeeps500Newest() {
        let usage = make(defaults(), transport: nil)
        for _ in 0..<300 { usage.count(.entry, now: at(1)) }
        for _ in 0..<300 { usage.count(.entry, now: at(2)) }
        #expect(usage.pending.count == UsageEvents.bufferLimit)
        #expect(!usage.pending.contains { $0.name == "installed" })
        #expect(usage.pending.last?.day == 1)
    }

    @Test("A day stops at 300 events")
    func aDayStopsAt300() {
        let usage = make(defaults(), transport: nil)
        for _ in 0..<400 { usage.count(.entry, now: at(1)) }
        #expect(usage.pending.count == UsageEvents.dailyLimit)
        usage.count(.entry, now: at(2))
        #expect(usage.pending.count == UsageEvents.dailyLimit + 1)
    }

    @Test("Once means the first outcome, gate and answer; each screen once")
    func onceMeansTheFirstOutcome() {
        let usage = make(defaults())
        usage.reach(.onboardingDone(.finished), now: at(1))
        usage.reach(.onboardingDone(.restored), now: at(1))
        usage.reach(.firstScreen(.home), now: at(1))
        usage.reach(.firstScreen(.history), now: at(1))
        usage.reach(.paywallFirst(.voice), now: at(1))
        usage.reach(.paywallFirst(.loanAdd), now: at(1))
        #expect(names(usage.pending) == ["installed", "onboarding_done:finished", "first_screen:home", "first_screen:history", "paywall_first:voice"])
    }

    @Test("Off empties the buffer and sends nothing; on again, sent milestones stay sent")
    func offClearsAndSendsNothing() async {
        let transport = RecordingTransport()
        let usage = make(defaults(), transport: transport)
        for _ in 0..<9 { usage.count(.entry, now: at(1)) }
        usage.reach(.tenOpened, now: at(1))
        usage.isEnabled = false
        #expect(usage.pending.isEmpty)
        await usage.flush()
        usage.reach(.captureFirst, now: at(1))
        usage.noteOpen(cold: true, now: at(2))
        #expect(usage.pending.isEmpty)
        #expect(transport.batches.isEmpty)
        usage.isEnabled = true
        usage.reach(.tenOpened, now: at(2))
        #expect(usage.pending.isEmpty)
        usage.reach(.captureFirst, now: at(2))
        await usage.flush()
        #expect(transport.batches.flatMap { $0 }.map(\.name) == ["capture_first"])
    }

    @Test("Silent in tests: nothing is ever queued")
    func silentInTests() {
        let usage = UsageEvents(defaults: defaults(), isSilent: true, transport: RecordingTransport(), traits: { UsageTraits() })
        usage.noteOpen(cold: true, now: at(1))
        usage.reach(.tenOpened, now: at(1))
        usage.count(.entry, now: at(1))
        #expect(usage.pending.isEmpty)
    }

    @Test("Pro: a trial starts, its renewal is turned off, it converts")
    func proTransitions() {
        func status(trial: Bool, renews: Bool, plan: ProStatus.Plan = .annual) -> ProStatus {
            ProStatus(plan: plan, expirationDate: at(15), willRenew: renews, managementURL: nil, isTrial: trial)
        }
        #expect(UsageEvents.proMilestones(from: nil, to: status(trial: true, renews: true)) == [.trialStarted])
        #expect(UsageEvents.proMilestones(from: status(trial: true, renews: true), to: status(trial: true, renews: false)) == [.renewalOff])
        #expect(UsageEvents.proMilestones(from: nil, to: status(trial: true, renews: false)) == [.trialStarted, .renewalOff])
        #expect(UsageEvents.proMilestones(from: status(trial: true, renews: true), to: status(trial: false, renews: true)) == [.converted])
        #expect(UsageEvents.proMilestones(from: status(trial: false, renews: true), to: nil).isEmpty)
        #expect(UsageEvents.proMilestones(from: status(trial: true, renews: false), to: status(trial: true, renews: false)).isEmpty)
    }

    @Test("A failed send keeps the batch; the third failure in a row drops it")
    func aFailedSendKeepsTheBatch() async {
        let transport = RecordingTransport()
        transport.failuresLeft = 1
        let usage = make(defaults(), transport: transport)
        usage.reach(.tenOpened, now: at(1))
        await usage.flush()
        #expect(usage.pending.count == 2)
        await usage.flush()
        #expect(usage.pending.isEmpty)
        #expect(transport.batches.count == 1)

        transport.failuresLeft = 3
        usage.count(.entry, now: at(1))
        await usage.flush()
        await usage.flush()
        #expect(usage.pending.count == 1)
        await usage.flush()
        #expect(usage.pending.isEmpty)
    }

    @Test("The wire carries the listed fields only: no identifier")
    func noIdentifierInTheWire() throws {
        let usage = make(defaults(), traits: UsageTraits(plan: "trial", entries: 7, reminder: true, capture: false, onboarding: "finished"))
        usage.reach(.tenOpened, now: at(1))
        let event = try #require(usage.pending.last)
        let data = try JSONEncoder().encode(["events": [event]])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]])
        let keys = Set(try #require(object["events"]?.first).keys)
        #expect(keys == ["kind", "name", "value", "cohort", "day", "plan", "entries", "reminder", "capture", "onboarding", "furthest0", "build", "ios", "lang"])
        #expect(event.entries == "5-9")
        #expect(event.plan == "trial")
        #expect(event.reminder)
    }

    @Test("The language and the build always pass the server's lists")
    func languageAndBuildAreSafe() {
        #expect(UsageEvents.languageCode("ru") == "ru")
        #expect(UsageEvents.languageCode("pt-BR") == "pt-BR")
        #expect(UsageEvents.languageCode("zh-Hans") == "zh")
        #expect(UsageEvents.languageCode(nil) == "en")
        #expect(UsageEvents.buildNumber("101") == "101")
        #expect(UsageEvents.buildNumber("1.10") == "0")
        #expect(UsageEvents.entriesBucket(0) == "0")
        #expect(UsageEvents.entriesBucket(4) == "2-4")
        #expect(UsageEvents.entriesBucket(50) == "50+")
    }

    @Test("A phone that used Tenra before keeps its first day and sends no install")
    func anExistingInstallIsNotNew() {
        let suite = defaults()
        suite.set(at(1, month: 10), forKey: "rating.installDate")
        let usage = make(suite)
        usage.noteOpen(cold: true, now: at(1))
        #expect(!usage.pending.contains { $0.name == "installed" })
        #expect(usage.pending.first?.cohort == UsageEvents.cohort(installedAt: at(1, month: 10)))
    }
}
