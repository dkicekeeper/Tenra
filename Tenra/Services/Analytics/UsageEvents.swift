//
//  UsageEvents.swift
//  Tenra
//
//  How far new people get and whether they come back (docs/plan-sales.md §4,
//  docs/domains/analytics.md): milestones, each sent once per install, and counters, posted in
//  batches to Tenra's server (`POST /v1/events`, server/assistant/src/events.ts). No identifier
//  of the install, the person or the device; no amounts, texts or names: every value is from a
//  fixed list, the same lists as the server's. Each milestone's count in an install week is
//  the number of installs that reached it.
//
//  Off with Settings › Privacy › "Anonymous usage statistics" (on by default): nothing is queued
//  or sent and the buffer is emptied. Silent in tests, UI tests and the screenshot demo.
//

import Foundation

/// The screens counted at their first visit.
enum UsageScreen: String, Sendable {
    case home, history, analytics, finances, assistant, add
    case importTab = "import"
    case settings, paywall, wardrobe

    /// A tab's screen; the voice tab is a feature, not a screen.
    init?(tab: AppTab) {
        switch tab {
        case .home: self = .home
        case .analytics: self = .analytics
        case .finances: self = .finances
        case .assistant: self = .assistant
        case .ocr: self = .importTab
        case .plusAction: self = .add
        case .voice: return nil
        }
    }
}

/// Features counted once a day each.
enum UsageFeature: String, Sendable {
    case budget, goal, debt, loan, deposit, asset
    case csvExport = "csv_export"
    case yearReview = "year_review"
    case voice, statement
}

enum UsageTenAction: String, Sendable {
    case asked
    case noticeOpened = "notice_opened"
    case noticeHidden = "notice_hidden"
}

enum UsagePaywallStep: String, Sendable {
    case shown, closed
    case purchaseStarted = "purchase_started"
    case purchased, cancelled, failed, restored
}

/// Sent once per install.
enum UsageMilestone: Hashable, Sendable {
    case installed
    case onboardingStep(ActivationAttributes.OnboardingStepReached)
    case onboardingDone(ActivationAttributes.OnboardingOutcome)
    case firstScreen(UsageScreen)
    /// Own entries reached 1, 5, 10 or 50.
    case entries(Int)
    case reminderOn
    case notifications(granted: Bool)
    case captureFirst
    case widgetOn
    case tenOpened
    case paywallFirst(PaywallSource)
    case trialStarted
    case renewalOff
    case converted
    /// The first open on day 1, 2, 3, 7, 14 or 30 after the install.
    case returned(day: Int)
    /// An open on any day from 7 to 13.
    case returnedWeek2
    /// A step of the first day's path passed, a skipped one included (`UsageEvents.path`), so
    /// the report's steps only fall along the path.
    case path(String)

    /// The entry counts worth a milestone.
    static let entryMilestones = [1, 5, 10, 50]
    /// The days worth a return milestone.
    static let returnDays = [1, 2, 3, 7, 14, 30]

    var wire: (name: String, value: String) {
        switch self {
        case .installed: ("installed", "")
        case .onboardingStep(let step): ("onboarding", step.rawValue)
        case .onboardingDone(let outcome): ("onboarding_done", outcome.rawValue)
        case .firstScreen(let screen): ("first_screen", screen.rawValue)
        case .entries(let count): ("entries", String(count))
        case .reminderOn: ("reminder_on", "")
        case .notifications(let granted): ("notifications", granted ? "granted" : "denied")
        case .captureFirst: ("capture_first", "")
        case .widgetOn: ("widget_on", "")
        case .tenOpened: ("ten_opened", "")
        case .paywallFirst(let source): ("paywall_first", source.rawValue)
        case .trialStarted: ("trial_started", "")
        case .renewalOff: ("renewal_off", "")
        case .converted: ("converted", "")
        case .returned(let day): ("returned", String(day))
        case .returnedWeek2: ("returned", "week2")
        case .path(let step): ("path", step)
        }
    }

    /// What makes it once: the first outcome, gate or answer only; each step, screen, entry
    /// count and return day once.
    var onceKey: String {
        switch self {
        case .onboardingDone: "onboarding_done"
        case .paywallFirst: "paywall_first"
        case .notifications: "notifications"
        default: "\(wire.name):\(wire.value)"
        }
    }

    /// Its place on the first day's path (`furthest0`), if it is on it.
    fileprivate var pathStep: String? {
        switch self {
        case .onboardingStep(let step): step.rawValue
        case .onboardingDone: "onboarding_done"
        case .entries(1): "entry"
        case .reminderOn: "reminder"
        default: nil
        }
    }
}

/// Counted every time (features once a day).
enum UsageCounter: Equatable, Sendable {
    case open(cold: Bool)
    case entry
    case paywall(UsagePaywallStep, source: PaywallSource, plan: ProStatus.Plan?)
    case feature(UsageFeature)
    case ten(UsageTenAction)
    case moment(TenMomentEvent)

    var wire: (name: String, value: String) {
        switch self {
        case .open(let cold): ("open", cold ? "cold" : "warm")
        case .entry: ("entry", "")
        case .paywall(let step, let source, let plan):
            ("paywall", "\(step.rawValue):\(source.rawValue):\(Self.planName(plan))")
        case .feature(let feature): ("feature", feature.rawValue)
        case .ten(let action): ("ten", action.rawValue)
        case .moment(let event): ("moment", Self.momentName(event))
        }
    }

    private static func planName(_ plan: ProStatus.Plan?) -> String {
        switch plan {
        case .monthly?: "monthly"
        case .annual?: "annual"
        case .lifetime?: "lifetime"
        case .unknown?, nil: "none"
        }
    }

    /// The kind of moment, never the goal's, debt's or asset's name.
    private static func momentName(_ event: TenMomentEvent) -> String {
        switch event {
        case .goalReached: "goal"
        case .debtSettled: "debt"
        case .loanPaidOff: "loan"
        case .assetSold: "asset"
        case .budgetMonth: "budget"
        case .firstCapture: "capture"
        }
    }
}

/// What every event says about where the person is now.
struct UsageTraits: Equatable, Sendable {
    var plan = "free"
    var entries = 0
    var reminder = false
    var capture = false
    var onboarding = "none"
}

/// One event as the server reads it (`UsageEventWire` in server/assistant/src/events.ts).
nonisolated struct UsageEvent: Codable, Equatable, Sendable {
    var kind: String
    var name: String
    var value: String
    var cohort: String
    var day: Int
    var plan: String
    var entries: String
    var reminder: Bool
    var capture: Bool
    var onboarding: String
    var furthest0: String
    var build: String
    var ios: String
    var lang: String
}

@MainActor
final class UsageEvents {
    static let shared = UsageEvents()

    /// The Settings switch; on unless turned off.
    nonisolated static let enabledKey = "usage.enabled"
    nonisolated static let batchSize = 100
    nonisolated static let bufferLimit = 500
    nonisolated static let dailyLimit = 300
    /// Sends of one batch that may fail in a row before it is dropped.
    nonisolated static let maxFailures = 3

    /// Where the person is now; AppCoordinator sets it.
    var traits: () -> UsageTraits

    private let defaults: UserDefaults
    private let isSilent: Bool
    private let transport: (any UsageEventsTransport)?
    private var buffer: [Queued]
    private var sent: Set<String>
    private var nextID: Int
    private var failures = 0
    private var isFlushing = false

    private struct Queued: Codable, Equatable {
        let id: Int
        let event: UsageEvent
    }

    private enum Key {
        static let installedAt = "usage.installedAt"
        static let sent = "usage.sent"
        static let furthest0 = "usage.furthest0"
        static let dayCount = "usage.dayCount"
        static let featureDays = "usage.featureDays"
        static let buffer = "usage.buffer"
        static let ownEntries = "usage.ownEntries"
        static let proPhase = "usage.proPhase"
    }

    /// The highest day since install the server takes: older installs say 400.
    nonisolated static let maxDay = 400

    /// The first day's path, in order (`furthest0`).
    nonisolated static let path = ["none", "welcome", "currency", "account", "categories", "capture", "onboarding_done", "entry", "reminder"]

    init(
        defaults: UserDefaults = .standard,
        isSilent: Bool = PremiumManager.isAutomatedRun,
        transport: (any UsageEventsTransport)? = HTTPUsageTransport.make(),
        traits: @escaping () -> UsageTraits = { UsageTraits() }
    ) {
        self.defaults = defaults
        self.isSilent = isSilent
        self.transport = transport
        self.traits = traits
        sent = Set(defaults.stringArray(forKey: Key.sent) ?? [])
        buffer = defaults.data(forKey: Key.buffer).flatMap { try? JSONDecoder().decode([Queued].self, from: $0) } ?? []
        nextID = (buffer.map(\.id).max() ?? 0) + 1
    }

    // MARK: - Switch

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue {
                buffer.removeAll()
                saveBuffer()
            }
        }
    }

    private var isActive: Bool { isEnabled && !isSilent }

    /// What is waiting to be sent, oldest first.
    var pending: [UsageEvent] { buffer.map(\.event) }

    // MARK: - Recording

    /// A milestone, once per install.
    func reach(_ milestone: UsageMilestone, now: Date = .now) {
        guard isActive else { return }
        ensureInstalled(now)
        let key = milestone.onceKey
        guard !sent.contains(key) else { return }
        let day = dayIndex(now)
        if day == 0, let step = milestone.pathStep { advanceFurthest(to: step, now: now) }
        // Milestones are few and once each: the day's cap is for counters only.
        append(kind: "m", wire: milestone.wire, day: day, now: now, capped: false)
        sent.insert(key)
        defaults.set(Array(sent), forKey: Key.sent)
    }

    /// A counter; a feature once a day.
    func count(_ counter: UsageCounter, now: Date = .now) {
        guard isActive else { return }
        ensureInstalled(now)
        if case .feature(let feature) = counter {
            var days = defaults.dictionary(forKey: Key.featureDays) as? [String: String] ?? [:]
            let today = Self.dayKey(now)
            guard days[feature.rawValue] != today else { return }
            days[feature.rawValue] = today
            defaults.set(days, forKey: Key.featureDays)
        }
        append(kind: "c", wire: counter.wire, day: dayIndex(now), now: now)
    }

    /// The app came to the front: the first time is the install; later, the return days.
    func noteOpen(cold: Bool, now: Date = .now) {
        guard isActive else { return }
        ensureInstalled(now)
        let day = dayIndex(now)
        if UsageMilestone.returnDays.contains(day) { reach(.returned(day: day), now: now) }
        if (7...13).contains(day) { reach(.returnedWeek2, now: now) }
        count(.open(cold: cold), now: now)
    }

    /// Records were added without an import (TransactionStore.onOwnRecords): the person's own
    /// ones (SpendingReminderPlan.isUserRecord, as the record streak) count one entry and move
    /// the own-entry count to its milestones 1, 5, 10 and 50. A series' payments, deposit
    /// interest and a statement's rows count nothing.
    func noteOwnRecords(_ transactions: [Transaction], now: Date = .now) {
        guard isActive else { return }
        let own = transactions.filter { SpendingReminderPlan.isUserRecord($0, now: now) }.count
        guard own > 0 else { return }
        let total = defaults.integer(forKey: Key.ownEntries) + own
        defaults.set(total, forKey: Key.ownEntries)
        count(.entry, now: now)
        for milestone in UsageMilestone.entryMilestones where total >= milestone {
            reach(.entries(milestone), now: now)
        }
    }

    /// The switch is off: Ten's turns go with `stats: false` (AgentServerClient). Read off the
    /// main actor.
    nonisolated static func isTurnedOff(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool == false
    }

    // MARK: - Sending

    /// Sends the oldest batch. Without a network it waits; one the server refuses three times in
    /// a row is dropped.
    func flush() async {
        guard isActive, !isFlushing, let transport, !buffer.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        let batch = Array(buffer.prefix(Self.batchSize))
        let ids = Set(batch.map(\.id))
        do {
            try await transport.send(batch.map(\.event))
            failures = 0
            buffer.removeAll { ids.contains($0.id) }
        } catch let error as UsageSendError where error.dropsBatch {
            // The server refused it: a batch it refuses three times in a row would block the rest.
            failures += 1
            if failures >= Self.maxFailures {
                failures = 0
                buffer.removeAll { ids.contains($0.id) }
            }
        } catch {
            // Offline, timed out, cancelled, rate limited: the batch waits for the next send.
        }
        saveBuffer()
    }

    // MARK: - Pro

    /// Where the Pro entitlement stands, as the counts need it.
    enum ProPhase: String {
        case none, trialRenewing, trialOff, paid
    }

    static func phase(of status: ProStatus?) -> ProPhase {
        guard let status else { return .none }
        if status.isTrial { return status.willRenew ? .trialRenewing : .trialOff }
        return .paid
    }

    /// The milestones a move between phases reaches.
    static func proMilestones(from old: ProPhase, to new: ProPhase) -> [UsageMilestone] {
        let wasTrial = old == .trialRenewing || old == .trialOff
        switch new {
        case .trialRenewing: return wasTrial ? [] : [.trialStarted]
        case .trialOff:
            if old == .trialRenewing { return [.renewalOff] }
            return old == .trialOff ? [] : [.trialStarted, .renewalOff]
        case .paid: return wasTrial ? [.converted] : []
        case .none: return []
        }
    }

    /// The entitlement as RevenueCat gives it now (PremiumManager): compared with the phase
    /// kept on the phone, so a trial that was paid while the app was closed still counts as
    /// converted on the next launch.
    func notePro(_ status: ProStatus?, now: Date = .now) {
        let new = Self.phase(of: status)
        let old = defaults.string(forKey: Key.proPhase).flatMap(ProPhase.init(rawValue:)) ?? .none
        guard new != old else { return }
        defaults.set(new.rawValue, forKey: Key.proPhase)
        for milestone in Self.proMilestones(from: old, to: new) { reach(milestone, now: now) }
    }

    // MARK: - Helpers

    /// The ISO-8601 week of the install, `yyyy-Www`, on a Gregorian calendar in the phone's time zone.
    nonisolated static func cohort(installedAt: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: installedAt)
        return String(format: "%04ld-W%02ld", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    nonisolated static func entriesBucket(_ count: Int) -> String {
        switch count {
        case ..<1: "0"
        case 1: "1"
        case 2...4: "2-4"
        case 5...9: "5-9"
        case 10...49: "10-49"
        default: "50+"
        }
    }

    /// The app's language as the server accepts it: `ru`, `pt-BR`; anything else by its first two letters.
    nonisolated static func languageCode(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "en" }
        if raw.range(of: "^[a-z]{2}(-[A-Z]{2})?$", options: .regularExpression) != nil { return raw }
        let letters = raw.prefix(2).lowercased()
        return letters.range(of: "^[a-z]{2}$", options: .regularExpression) != nil ? letters : "en"
    }

    /// The build number as the server accepts it: digits only.
    nonisolated static func buildNumber(_ raw: String?) -> String {
        guard let raw, raw.range(of: "^\\d{1,6}$", options: .regularExpression) != nil else { return "0" }
        return raw
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The install day. A phone that used Tenra before these counts keeps its first day and
    /// sends no `installed`: its week is not a new install's.
    private var installedAt: Date? {
        defaults.object(forKey: Key.installedAt) as? Date
    }

    private func ensureInstalled(_ now: Date) {
        guard installedAt == nil else { return }
        let calendar = Self.calendar
        if let known = RatingPromptService.installDate(defaults: defaults),
           calendar.startOfDay(for: known) < calendar.startOfDay(for: now) {
            defaults.set(known, forKey: Key.installedAt)
            return
        }
        defaults.set(now, forKey: Key.installedAt)
        reach(.installed, now: now)
    }

    private func dayIndex(_ now: Date) -> Int {
        guard let installedAt else { return 0 }
        let calendar = Self.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: installedAt), to: calendar.startOfDay(for: now)).day ?? 0
        return min(max(0, days), Self.maxDay)
    }

    private var furthest0: String {
        defaults.string(forKey: Key.furthest0) ?? "none"
    }

    /// The first day went further: every step passed on the way, skipped ones included, is a
    /// `path` milestone.
    private func advanceFurthest(to step: String, now: Date) {
        guard let new = Self.path.firstIndex(of: step), let old = Self.path.firstIndex(of: furthest0), new > old else { return }
        defaults.set(step, forKey: Key.furthest0)
        for passed in Self.path[(old + 1)...new] { reach(.path(passed), now: now) }
    }

    private func append(kind: String, wire: (name: String, value: String), day: Int, now: Date, capped: Bool = true) {
        // The day's cap for counters: past it, that day's counters are dropped.
        if capped {
            let today = Self.dayKey(now)
            let stored = defaults.string(forKey: Key.dayCount)?.split(separator: "|").map(String.init) ?? []
            let countToday = stored.count == 2 && stored[0] == today ? Int(stored[1]) ?? 0 : 0
            guard countToday < Self.dailyLimit else { return }
            defaults.set("\(today)|\(countToday + 1)", forKey: Key.dayCount)
        }

        let person = self.traits()
        let event = UsageEvent(
            kind: kind,
            name: wire.name,
            value: wire.value,
            cohort: Self.cohort(installedAt: installedAt ?? now),
            day: day,
            plan: person.plan,
            entries: Self.entriesBucket(person.entries),
            reminder: person.reminder,
            capture: person.capture,
            onboarding: person.onboarding,
            furthest0: furthest0,
            build: Self.buildNumber(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
            ios: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
            lang: Self.languageCode(Bundle.main.preferredLocalizations.first)
        )
        buffer.append(Queued(id: nextID, event: event))
        nextID += 1
        if buffer.count > Self.bufferLimit { buffer.removeFirst(buffer.count - Self.bufferLimit) }
        saveBuffer()
    }

    private func saveBuffer() {
        defaults.set(try? JSONEncoder().encode(buffer), forKey: Key.buffer)
    }
}
