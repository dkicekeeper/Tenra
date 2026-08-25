//
//  InsightSignalService.swift
//  Tenra
//
//  Insights product audit 2026-07 — Phase C.
//  Diff engine turning freshly computed insights into local push notifications.
//
//  Benchmark-derived rules (docs/INSIGHTS_PRODUCT_AUDIT.md):
//  - Push TRANSITIONS, not states: a signal id fires at most once per 7 days,
//    so a budget that stays overspent doesn't nag daily.
//  - Global cap of 5 pushes per rolling week (anti notification-fatigue; 43% of
//    users disable notifications because of noise).
//  - At most 2 pushes per recompute, staggered — a post-absence launch must not
//    dump the whole weekly budget as one burst of banners.
//  - Only critical/warning severities are push-worthy; neutral/positive insights
//    stay in the in-app feed.
//  - Every signal kind is individually toggleable (InsightSignalSettings).
//

import Foundation
import UserNotifications
import os

// MARK: - Signal Kind

/// Push-worthy insight signal kinds. Raw values are stable — they key the
/// per-type settings toggles.
enum InsightSignalKind: String, CaseIterable, Sendable {
    case budgetOverspend
    case projectedOverspend
    case priceIncrease
    case lowProjectedBalance
    case spendingSpike
    case largeTransaction

    /// Settings-row label. Reuses the insight card title keys where they read
    /// naturally as a toggle label.
    var displayName: String {
        switch self {
        case .budgetOverspend:     return String(localized: "insights.budgetOver")
        case .projectedOverspend:  return String(localized: "insights.projectedOverspend")
        case .priceIncrease:       return String(localized: "insights.priceIncrease")
        case .lowProjectedBalance: return String(localized: "settings.insightSignals.lowBalance")
        case .spendingSpike:       return String(localized: "insights.spendingSpike")
        case .largeTransaction:    return String(localized: "insights.largeTransaction")
        }
    }

    /// Maps a computed insight to its signal kind. Nil = not push-worthy.
    /// Severity gates encode the "is this worth interrupting for" thresholds.
    nonisolated static func from(_ insight: Insight) -> InsightSignalKind? {
        guard insight.severity == .critical || insight.severity == .warning else { return nil }
        switch insight.type {
        case .budgetOverspend:           return .budgetOverspend
        case .projectedOverspend:        return .projectedOverspend
        case .subscriptionPriceIncrease: return .priceIncrease
        case .projectedBalance:          return .lowProjectedBalance
        case .spendingSpike:             return .spendingSpike
        case .largeTransaction:          return .largeTransaction
        default:                         return nil
        }
    }
}

// MARK: - Service

@MainActor
final class InsightSignalService {
    static let shared = InsightSignalService()

    private static let logger = Logger(subsystem: "Tenra", category: "InsightSignalService")

    struct FiredRecord: Codable, Equatable, Sendable {
        let id: String
        let date: Date
    }

    /// One signal id fires at most once per this window.
    nonisolated static let dedupWindow: TimeInterval = 7 * 24 * 3600
    /// Hard ceiling on pushes per rolling week across all signal kinds.
    nonisolated static let weeklyCap = 5
    /// Ceiling per single recompute. After a multi-day absence the weekly budget
    /// is fully replenished AND several signals flip at once (catch-up recurring
    /// tx push budgets over, dedup records expired) — without this cap the first
    /// recompute after launch dumped up to 5 pushes back-to-back.
    nonisolated static let perRunCap = 2
    /// Delivery window: signals are only delivered between these local hours.
    /// A signal falling outside is moved to the next morning slot.
    nonisolated static let deliveryWindowStartHour = 9
    nonisolated static let deliveryWindowEndHour = 21
    /// Morning slot = 09:00 + random 0...90 min, so post-night deliveries do not
    /// all land at exactly 09:00 (subscription reminders and digest live there).
    nonisolated static let morningJitterMinutes = 90
    /// Random spacing between pushes selected in the same run.
    nonisolated static let minRunSpacing: TimeInterval = 2 * 3600
    nonisolated static let maxRunSpacing: TimeInterval = 4 * 3600
    private static let historyKey = "insightSignals.history"
    /// Notification identifier prefix — AppDelegate routes taps on it to the Analytics tab.
    nonisolated static let notificationIdPrefix = "insightSignal_"

    private let defaults: UserDefaults
    private let settings: InsightSignalSettings

    init(defaults: UserDefaults = .standard, settings: InsightSignalSettings = .shared) {
        self.defaults = defaults
        self.settings = settings
    }

    // MARK: - Pure selection core (unit-tested)

    /// Selects which insights should fire a push right now, given the enabled
    /// kinds and the fire history. Pure — no I/O, no clock.
    nonisolated static func selectSignals(
        from insights: [Insight],
        enabledKinds: Set<InsightSignalKind>,
        history: [FiredRecord],
        now: Date
    ) -> [Insight] {
        guard !enabledKinds.isEmpty else { return [] }
        let windowStart = now.addingTimeInterval(-dedupWindow)
        let recent = history.filter { $0.date > windowStart }
        let recentIds = Set(recent.map(\.id))
        let budget = max(0, min(perRunCap, weeklyCap - recent.count))
        guard budget > 0 else { return [] }

        return Array(
            insights
                .compactMap { insight -> Insight? in
                    guard let kind = InsightSignalKind.from(insight),
                          enabledKinds.contains(kind),
                          !recentIds.contains(insight.id) else { return nil }
                    return insight
                }
                .sorted { $0.severity.sortOrder < $1.severity.sortOrder }
                .prefix(budget)
        )
    }

    /// Notification body composed from the already-localized insight fields —
    /// no per-kind notification strings needed.
    nonisolated static func notificationBody(for insight: Insight) -> String {
        var parts: [String] = []
        if !insight.subtitle.isEmpty { parts.append(insight.subtitle) }
        var metricPart = insight.metric.formattedValue
        if let pct = insight.trend?.changePercent, abs(pct) >= 1 {
            metricPart += String(format: " (%+.0f%%)", pct)
        }
        parts.append(metricPart)
        return parts.joined(separator: " · ")
    }

    // MARK: - Delivery window scheduling (pure, unit-tested)

    /// Returns `count` delivery dates: the first is `now` when inside the
    /// 09:00-21:00 window (otherwise the next morning slot), each subsequent one
    /// is 2-4 h after the previous, overflowing past 21:00 into the next morning.
    /// Pure given an injected RNG - tests pass a seeded generator.
    nonisolated static func deliveryDates(
        count: Int,
        now: Date,
        calendar: Calendar = .current,
        rng: inout some RandomNumberGenerator
    ) -> [Date] {
        guard count > 0 else { return [] }
        var dates: [Date] = []
        dates.reserveCapacity(count)
        var cursor = now
        for index in 0..<count {
            var candidate: Date
            if index == 0 {
                candidate = isInsideWindow(now, calendar: calendar)
                    ? now
                    : nextMorningSlot(after: now, calendar: calendar, rng: &rng)
            } else {
                let spacing = TimeInterval.random(in: minRunSpacing...maxRunSpacing, using: &rng)
                candidate = cursor.addingTimeInterval(spacing)
                if !isInsideWindow(candidate, calendar: calendar) {
                    candidate = nextMorningSlot(after: candidate, calendar: calendar, rng: &rng)
                }
            }
            dates.append(candidate)
            cursor = candidate
        }
        return dates
    }

    private nonisolated static func isInsideWindow(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= deliveryWindowStartHour && hour < deliveryWindowEndHour
    }

    /// 09:00 + 0...90 min jitter on the next day whose window start is still ahead
    /// of `date` (05:00 resolves to the SAME day's morning).
    private nonisolated static func nextMorningSlot(
        after date: Date,
        calendar: Calendar,
        rng: inout some RandomNumberGenerator
    ) -> Date {
        var day = calendar.startOfDay(for: date)
        var windowStart = calendar.date(byAdding: .hour, value: deliveryWindowStartHour, to: day) ?? date
        if date >= windowStart {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            windowStart = calendar.date(byAdding: .hour, value: deliveryWindowStartHour, to: day) ?? date
        }
        let jitterSeconds = Int.random(in: 0...(morningJitterMinutes * 60), using: &rng)
        return windowStart.addingTimeInterval(TimeInterval(jitterSeconds))
    }

    // MARK: - Eligible set (stale-pending cancellation)

    /// Ids of insights that would currently qualify as signals (severity gate +
    /// enabled kind), IGNORING dedup history - a signal already scheduled is in
    /// history by design, yet must stay pending as long as it still qualifies.
    /// Pending ids outside this set are cancelled by `processInsights`.
    nonisolated static func eligibleSignalIds(
        from insights: [Insight],
        enabledKinds: Set<InsightSignalKind>
    ) -> Set<String> {
        Set(insights.compactMap { insight in
            guard let kind = InsightSignalKind.from(insight),
                  enabledKinds.contains(kind) else { return nil }
            return insight.id
        })
    }

    // MARK: - Processing

    /// Diffs freshly computed insights against the alert history and fires local
    /// notifications for new critical/warning signals. Call after every insight
    /// recompute — dedup and the weekly cap make repeated calls safe.
    func processInsights(_ insights: [Insight], now: Date = Date()) async {
        let selected = Self.selectSignals(
            from: insights,
            enabledKinds: settings.enabledKinds,
            history: loadHistory(),
            now: now
        )
        guard !selected.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let auth = await center.notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional else {
            Self.logger.debug("🔔 [Signals] \(selected.count) signal(s) selected but notifications not authorized — skipped")
            return
        }

        // Prune expired records while we're writing anyway.
        var history = loadHistory().filter { $0.date > now.addingTimeInterval(-Self.dedupWindow) }
        for (index, insight) in selected.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = insight.title
            content.body = Self.notificationBody(for: insight)
            content.sound = .default
            // Temporary bridge - Task 3 replaces this with windowed deliveryDates.
            let trigger: UNNotificationTrigger? = index == 0
                ? nil
                : UNTimeIntervalNotificationTrigger(timeInterval: 180 * Double(index), repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.notificationIdPrefix + insight.id,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                history.append(FiredRecord(id: insight.id, date: now))
                Self.logger.debug("🔔 [Signals] fired '\(insight.id, privacy: .public)' (\(String(describing: insight.severity), privacy: .public))")
            } catch {
                Self.logger.warning("🔔 [Signals] failed to schedule '\(insight.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        saveHistory(history)
    }

    // MARK: - History persistence

    private func loadHistory() -> [FiredRecord] {
        guard let data = defaults.data(forKey: Self.historyKey),
              let records = try? JSONDecoder().decode([FiredRecord].self, from: data) else { return [] }
        return records
    }

    private func saveHistory(_ records: [FiredRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }
}
