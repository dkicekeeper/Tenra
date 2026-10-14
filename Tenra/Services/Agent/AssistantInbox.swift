//
//  AssistantInbox.swift
//  Tenra
//
//  Ten writes first (docs/plan-ai-assistant.md, phase 3): what the app already notices becomes a
//  message from the assistant. A critical or warning insight (the same kinds that may push,
//  InsightSignalKind), last week's summary once a week, and a subscription charged tomorrow.
//  Messages wait in this inbox until the person goes through them or closes them on Home ("Ten
//  writes", AssistantNoticesSection; never in the chat). Going through one is a question like
//  any other, so it spends a free answer (plan §6: messages are free to read, the analysis is
//  not).
//
//  Each message has a key that never posts twice (an insight's id or signal key, the week, the
//  series and its charge day). New insight messages are capped per day, so a bad week reads as
//  one or two notes, not a wall. The inbox lives in UserDefaults: small, and only this device's.
//

import Foundation
import Observation

/// A message Ten wrote first.
struct AssistantNotice: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case signal
        case digest
        case charge
    }

    enum Mood: String, Codable, Sendable {
        case idle, happy, concerned, celebrate
    }

    /// The key that keeps it from posting twice.
    var id: String
    var kind: Kind
    var title: String
    var body: String
    var mood: Mood
    /// What "Go through it" asks.
    var question: String
    /// The insight it came from, for the model to look up.
    var insightId: String?
    var createdAt: Date
    var isRead = false

    /// The `<notice>` block that goes with the question, so the model knows what it answers.
    var modelText: String {
        var fields: [String: JSONValue] = [:]
        fields["kind"] = .string(kind.rawValue)
        fields["title"] = .string(title)
        fields["text"] = .string(body)
        fields["insight_id"] = insightId.map(JSONValue.string) ?? .null
        return "<notice>\n\(JSONValue.object(fields).jsonString())\n</notice>"
    }
}

// MARK: - What becomes a message

enum AssistantNotices {
    /// Insight messages a day, at most.
    static let signalsPerDay = 2

    /// Critical and warning insights of the kinds that may push, worst first.
    static func signals(from insights: [Insight], now: Date) -> [AssistantNotice] {
        insights
            .filter { InsightSignalKind.from($0) != nil }
            .sorted { lhs, rhs in
                if lhs.severity == rhs.severity { return lhs.id < rhs.id }
                return lhs.severity == .critical
            }
            .map { insight in
                AssistantNotice(
                    id: "signal:\(insight.signalKey ?? insight.id)",
                    kind: .signal,
                    title: insight.title,
                    body: InsightSignalService.notificationBody(for: insight),
                    mood: .concerned,
                    question: String(format: String(localized: "assistant.notice.ask"), insight.title),
                    insightId: insight.id,
                    createdAt: now
                )
            }
    }

    /// Last week's summary: the week before the current one, against the week before it. Nil
    /// without expenses that week.
    static func digest(weekPoints: [PeriodDataPoint], baseCurrency: String, now: Date) -> AssistantNotice? {
        let currentKey = InsightGranularity.week.currentPeriodKey
        guard let currentIndex = weekPoints.lastIndex(where: { $0.key == currentKey }), currentIndex > 0 else { return nil }
        let week = weekPoints[currentIndex - 1]
        guard week.expenses > 0 else { return nil }
        let weekLabel = InsightGranularity.week.headingLabel(for: week.key)
        let spent = Formatting.formatCurrencySmart(week.expenses, currency: baseCurrency)
        var body = String(format: String(localized: "notification.weeklyDigest.body.simple"), weekLabel, spent)
        var mood = AssistantNotice.Mood.idle
        if currentIndex > 1 {
            let before = weekPoints[currentIndex - 2]
            if before.expenses > 0 {
                let change = (week.expenses - before.expenses) / before.expenses * 100
                body = String(
                    format: String(localized: "notification.weeklyDigest.body.withComparison"),
                    weekLabel, spent, String(format: "%+.0f%%", change)
                )
                mood = change <= -5 ? .happy : (change >= 20 ? .concerned : .idle)
            }
        }
        return AssistantNotice(
            id: "digest:\(week.key)",
            kind: .digest,
            title: String(localized: "notification.weeklyDigest.title"),
            body: body,
            mood: mood,
            question: String(localized: "assistant.notice.ask.digest"),
            insightId: nil,
            createdAt: now
        )
    }

    /// Subscriptions charged tomorrow.
    static func charges(
        subscriptions: [RecurringSeries],
        nextCharge: (RecurringSeries) -> Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> [AssistantNotice] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return subscriptions.compactMap { series in
            guard let date = nextCharge(series), calendar.isDate(date, inSameDayAs: tomorrow) else { return nil }
            let amount = Formatting.formatCurrencySmart(NSDecimalNumber(decimal: series.amount).doubleValue, currency: series.currency)
            return AssistantNotice(
                id: "charge:\(series.id):\(FastDateParser.string(from: tomorrow))",
                kind: .charge,
                title: series.description,
                body: String(format: String(localized: "assistant.notice.charge"), amount),
                mood: .idle,
                question: String(format: String(localized: "assistant.notice.ask.charge"), series.description),
                insightId: nil,
                createdAt: now
            )
        }
    }
}

// MARK: - Inbox

@Observable
final class AssistantInbox {
    static let shared = AssistantInbox()

    /// Kept messages, newest first.
    private(set) var notices: [AssistantNotice] = []

    @ObservationIgnored private let defaults: UserDefaults
    /// Every key ever posted, with when: a message gone from the list still never posts again.
    @ObservationIgnored private var posted: [String: Date] = [:]

    /// Messages kept in the list.
    static let keep = 20
    /// How long a posted key is remembered.
    static let rememberDays = 90

    private static let storageKey = "assistant.inbox.v1"

    private struct Stored: Codable {
        var notices: [AssistantNotice]
        var posted: [String: Date]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            notices = stored.notices
            posted = stored.posted
        }
    }

    var unread: [AssistantNotice] { notices.filter { !$0.isRead } }

    /// Posts what was never posted. Insight messages stop at `signalsPerDay` a day.
    func post(_ candidates: [AssistantNotice], now: Date = Date(), calendar: Calendar = .current) {
        var signalsToday = posted.filter { $0.key.hasPrefix("signal:") && calendar.isDate($0.value, inSameDayAs: now) }.count
        var added = false
        for notice in candidates where posted[notice.id] == nil {
            if notice.kind == .signal {
                guard signalsToday < AssistantNotices.signalsPerDay else { continue }
                signalsToday += 1
            }
            posted[notice.id] = now
            notices.insert(notice, at: 0)
            added = true
        }
        guard added else { return }
        if notices.count > Self.keep { notices.removeLast(notices.count - Self.keep) }
        if let horizon = calendar.date(byAdding: .day, value: -Self.rememberDays, to: now) {
            posted = posted.filter { $0.value >= horizon }
        }
        save()
    }

    func markRead(_ id: String) {
        guard let index = notices.firstIndex(where: { $0.id == id }), !notices[index].isRead else { return }
        notices[index].isRead = true
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Stored(notices: notices, posted: posted)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
