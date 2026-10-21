//
//  AssistantInbox.swift
//  Tenra
//
//  Ten writes first (docs/domains/assistant.md §6): what the app already notices becomes a
//  message from the assistant. A critical or warning insight (the same kinds that may push,
//  InsightSignalKind), last week's summary once a week, a subscription charged tomorrow, a
//  personal debt due tomorrow, and a savings goal fallen behind its schedule (once a month).
//  Messages wait in this inbox until the person goes through them or closes them on Home ("Ten
//  writes", AssistantNoticesSection; never in the chat). Going through one is a question like
//  any other, so it spends a free answer (docs/domains/assistant.md §11: messages are free to read, the analysis is
//  not).
//
//  Each message has a key that never posts twice (an insight's id or signal key, the week, the
//  series and its charge day, the debt and its due day, the goal and the month). New insight messages are capped per day, so a bad week reads as
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
        /// A personal debt due tomorrow.
        case debt
        /// A savings goal behind its schedule.
        case goal
    }

    enum Mood: String, Codable, Sendable {
        case idle, happy, concerned, celebrate
        /// An unusually large expense or a sudden jump.
        case surprised
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
    /// The debt or the goal it is about, for the model to look up.
    var subjectId: String? = nil
    var createdAt: Date
    var isRead = false

    /// The `<notice>` block that goes with the question, so the model knows what it answers.
    var modelText: String {
        var fields: [String: JSONValue] = [:]
        fields["kind"] = .string(kind.rawValue)
        fields["title"] = .string(title)
        fields["text"] = .string(body)
        fields["insight_id"] = insightId.map(JSONValue.string) ?? .null
        switch kind {
        case .debt: fields["debt_id"] = subjectId.map(JSONValue.string) ?? .null
        case .goal: fields["goal_id"] = subjectId.map(JSONValue.string) ?? .null
        default: break
        }
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
                    mood: InsightSignalKind.from(insight)?.isSurprise == true ? .surprised : .concerned,
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

extension AssistantNotices {
    /// Open debts due tomorrow, either way.
    static func debtsDue(_ debts: [PersonalDebt], now: Date, calendar: Calendar = .current) -> [AssistantNotice] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return debts.compactMap { debt in
            guard !debt.isSettled, let due = debt.dueDate, calendar.isDate(due, inSameDayAs: tomorrow) else { return nil }
            let amount = Formatting.formatCurrencySmart(debt.remaining, currency: debt.currency)
            let owedToMe = debt.direction == .owedToMe
            return AssistantNotice(
                id: "debt:\(debt.id):\(FastDateParser.string(from: tomorrow))",
                kind: .debt,
                title: debt.person,
                body: String(format: owedToMe
                    ? String(localized: "assistant.notice.debt.owedToMe")
                    : String(localized: "assistant.notice.debt.iOwe"), amount),
                mood: owedToMe ? .idle : .concerned,
                question: String(format: String(localized: "assistant.notice.ask.debt"), debt.person),
                insightId: nil,
                subjectId: debt.id,
                createdAt: now
            )
        }
    }

    /// Goals behind their schedule: with a deadline, not reached, started a month ago or more,
    /// and saved less than the time gone asks for by a fifth of the target or more. Once a month
    /// per goal.
    static func goalsBehind(
        _ goals: [SavingsGoal],
        saved: (SavingsGoal) -> Double,
        now: Date,
        calendar: Calendar = .current
    ) -> [AssistantNotice] {
        goals.compactMap { goal in
            guard let deadline = goal.deadline else { return nil }
            let status = GoalProgress.status(target: goal.targetAmount, saved: saved(goal), deadline: deadline, today: now, calendar: calendar)
            guard !status.isReached, let monthly = status.monthly else { return nil }
            let span = deadline.timeIntervalSince(goal.createdAt)
            let gone = now.timeIntervalSince(goal.createdAt)
            guard span > 0, gone >= Self.goalGraceDays * 86_400 else { return nil }
            guard status.fraction < min(1, gone / span) - Self.goalBehindShare else { return nil }
            let month = String(FastDateParser.string(from: now).prefix(7))
            return AssistantNotice(
                id: "goal:\(goal.id):\(month)",
                kind: .goal,
                title: goal.name,
                body: String(
                    format: String(localized: "assistant.notice.goal.behind"),
                    Formatting.formatCurrencySmart(monthly, currency: goal.currency),
                    DateFormatters.displayDateOmittingCurrentYear(deadline)
                ),
                mood: .concerned,
                question: String(format: String(localized: "assistant.notice.ask.goal"), goal.name),
                insightId: nil,
                subjectId: goal.id,
                createdAt: now
            )
        }
    }

    /// A goal younger than this is never behind.
    static let goalGraceDays: Double = 30
    /// How far below the time gone the saved share must fall.
    static let goalBehindShare = 0.2
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

    /// "Delete all data" or a restored backup: the messages name the old data's goals, debts
    /// and subscriptions. What the new data calls for posts again on the next refresh.
    func clear() {
        notices = []
        posted = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Stored(notices: notices, posted: posted)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
