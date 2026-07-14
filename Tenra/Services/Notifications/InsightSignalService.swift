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
        let budget = max(0, weeklyCap - recent.count)
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
        for insight in selected {
            let content = UNMutableNotificationContent()
            content.title = insight.title
            content.body = Self.notificationBody(for: insight)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: Self.notificationIdPrefix + insight.id,
                content: content,
                trigger: nil // deliver now
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
