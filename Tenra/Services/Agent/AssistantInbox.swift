//
//  AssistantInbox.swift
//  Tenra
//
//  Ten writes first (docs/domains/assistant.md §6): what the app already notices becomes a
//  message from the assistant. A critical or warning insight (the same kinds that may push,
//  InsightSignalKind), last week's summary once a week, a subscription charged tomorrow, a
//  personal debt due tomorrow, a savings goal fallen behind its schedule (once a month), and an
//  asset whose valuation is out of date (once a half-year; its button opens the valuation, not
//  Ten, who does not see assets yet).
//  Messages wait in this inbox until the person goes through them or closes them on Home ("Ten
//  writes", AssistantNoticesSection; never in the chat). Going through one is a question like
//  any other, so it spends a free answer (docs/domains/assistant.md §11: messages are free to read, the analysis is
//  not).
//
//  Each message has a key that never posts twice (an insight's id or signal key, the week, the
//  series and its charge day, the debt and its due day, the goal and the month, the asset and the
//  half-year). New insight messages are capped per day, so a bad week reads as
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
        /// Auto-capture not set up yet: its action opens the Wallet guide, not Ten.
        case setup
        /// An asset's valuation out of date: its action opens a new valuation, not Ten.
        case asset
        /// A long loan no asset is bought with (plan-assets-roadmap 1.2): its action opens a new
        /// asset with the loan, not Ten.
        case loanAsset
        /// "What do you think of Tenra?" (FeedbackAsk): its action opens FeedbackSheet, not Ten.
        case feedback
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
    /// `body` with its amounts as dots, shown while "hide amounts" is on. nil for a message
    /// without amounts and for one kept before the field existed (then the body shows).
    var hiddenBody: String? = nil
    /// What `body` and `hiddenBody` are written from, so a change in Settings › Formats writes
    /// them again (`AssistantInbox.rewriteTexts`). nil for an insight's message (its words come
    /// from the insight) and for one kept before the field existed.
    var text: AssistantNoticeText? = nil
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

extension AssistantNotice {
    /// As the synthesized decoder, except `text`: values another version wrote (a value case
    /// renamed, removed or added) drop only this message's values. The inbox decodes all or
    /// nothing, so a failure here would lose every message and every posted key.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        hiddenBody = try container.decodeIfPresent(String.self, forKey: .hiddenBody)
        text = try? container.decodeIfPresent(AssistantNoticeText.self, forKey: .text)
        mood = try container.decode(Mood.self, forKey: .mood)
        question = try container.decode(String.self, forKey: .question)
        insightId = try container.decodeIfPresent(String.self, forKey: .insightId)
        subjectId = try container.decodeIfPresent(String.self, forKey: .subjectId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }
}

/// A message's words as a localized format and the values it is filled with, so the words can
/// be written again in other formats: the amounts and the days follow Settings › Formats.
///
/// ⚠️ The format keys are stored with their values in every kept message: a key's arguments
/// (their number, order or kind) never change; a new wording with other arguments takes a new
/// key. A key that no longer resolves or no longer takes exactly these values is not used: the
/// message keeps its stored words.
struct AssistantNoticeText: Codable, Equatable, Sendable {
    enum Value: Codable, Equatable, Sendable {
        /// An amount; dots while "hide amounts" is on.
        case amount(Double, currency: String)
        /// An amount with "+" before it when it is not negative (the projected balance).
        case signedAmount(Double, currency: String)
        /// A day date, its year only outside the current one.
        case day(Date)
        /// A week from its first day ("3 ноября 2026 – 9 ноября 2026").
        case week(start: Date)
        /// Words the formats leave as they are.
        case text(String)
    }

    /// The `Localizable.strings` key of the format.
    var format: String
    var values: [Value]

    /// The words in the formats in force; nil when the key no longer resolves or no longer
    /// takes exactly these values (another version changed it), so the stored words stay.
    var body: String? { written(hidingAmounts: false) }
    var hiddenBody: String? { written(hidingAmounts: true) }

    /// How many string arguments `format` takes: its `%@` or its distinct `%n$@` (positions
    /// 1...n, none skipped). nil when it takes anything else, mixes the two, or skips one.
    static func objectArguments(in format: String) -> Int? {
        let characters = Array(format)
        var plain = 0
        var positions = Set<Int>()
        var index = 0
        while index < characters.count {
            guard characters[index] == "%" else { index += 1; continue }
            index += 1
            guard index < characters.count else { return nil }
            if characters[index] == "%" { index += 1; continue }
            var digits = ""
            while index < characters.count, characters[index].isASCII, characters[index].isNumber {
                digits.append(characters[index])
                index += 1
            }
            var position: Int?
            if !digits.isEmpty {
                guard index < characters.count, characters[index] == "$", let number = Int(digits), number > 0 else { return nil }
                position = number
                index += 1
            }
            guard index < characters.count, characters[index] == "@" else { return nil }
            index += 1
            if let position { positions.insert(position) } else { plain += 1 }
        }
        guard !positions.isEmpty else { return plain }
        guard plain == 0, positions == Set(1...positions.count) else { return nil }
        return positions.count
    }

    private func written(hidingAmounts: Bool) -> String? {
        let resolved = String(localized: String.LocalizationValue(format))
        guard resolved != format, Self.objectArguments(in: resolved) == values.count else { return nil }
        let arguments: [String] = values.map { value in
            switch value {
            case let .amount(amount, currency):
                hidingAmounts
                    ? Formatting.hiddenAmount(currency: currency)
                    : Formatting.formatCurrencySmart(amount, currency: currency)
            case let .signedAmount(amount, currency):
                hidingAmounts
                    ? Formatting.hiddenAmount(currency: currency)
                    : (amount >= 0 ? "+" : "") + Formatting.formatCurrencySmart(amount, currency: currency)
            case let .day(date):
                DateFormatters.displayDateOmittingCurrentYear(date)
            case let .week(start):
                InsightGranularity.weekBannerLabel(startingOn: start).capitalizedFirstLetter
            case let .text(text):
                text
            }
        }
        return String(format: resolved, arguments: arguments)
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
                let text = signalText(for: insight)
                return AssistantNotice(
                    id: "signal:\(insight.signalKey ?? insight.id)",
                    kind: .signal,
                    title: insight.title,
                    body: text?.body ?? InsightSignalService.notificationBody(for: insight),
                    hiddenBody: text?.hiddenBody ?? InsightSignalService.hiddenNotificationBody(for: insight),
                    text: text,
                    mood: InsightSignalKind.from(insight)?.isSurprise == true ? .surprised : .concerned,
                    question: String(format: String(localized: "assistant.notice.ask"), insight.title),
                    insightId: insight.id,
                    createdAt: now
                )
            }
    }

    /// An insight message's values, read as `InsightSignalService.notificationBody` writes the
    /// push: the subtitle as words, the value as an amount, the change as words. nil when the
    /// words hold what the values cannot write again: an amount in the subtitle
    /// (`hiddenSubtitle`), the large expense's day, a value not written by `formatCurrencySmart`
    /// (or with its "+"), an empty subtitle, a value without a currency. Such a message keeps
    /// its words.
    static func signalText(for insight: Insight) -> AssistantNoticeText? {
        guard !insight.subtitle.isEmpty, insight.hiddenSubtitle == nil, insight.type != .largeTransaction,
              let currency = insight.metric.currency else { return nil }
        let metric = insight.metric
        let written = Formatting.formatCurrencySmart(metric.value, currency: currency)
        let amount: AssistantNoticeText.Value
        if metric.formattedValue == written {
            amount = .amount(metric.value, currency: currency)
        } else if metric.formattedValue == "+" + written, metric.value >= 0 {
            amount = .signedAmount(metric.value, currency: currency)
        } else {
            return nil
        }
        let text: AssistantNoticeText
        if let percent = insight.trend?.changePercent, abs(percent) >= 1 {
            text = AssistantNoticeText(
                format: "assistant.notice.signal.change",
                values: [.text(insight.subtitle), amount, .text(String(format: "%+.0f%%", percent))]
            )
        } else {
            text = AssistantNoticeText(format: "assistant.notice.signal", values: [.text(insight.subtitle), amount])
        }
        return text.body == nil ? nil : text
    }

    /// Last week's summary: the week before the current one, against the week before it. Nil
    /// without expenses that week.
    static func digest(weekPoints: [PeriodDataPoint], baseCurrency: String, now: Date) -> AssistantNotice? {
        let currentKey = InsightGranularity.week.currentPeriodKey
        guard let currentIndex = weekPoints.lastIndex(where: { $0.key == currentKey }), currentIndex > 0 else { return nil }
        let week = weekPoints[currentIndex - 1]
        guard week.expenses > 0 else { return nil }
        let weekStart = InsightGranularity.week.periodStart(for: week.key)
        var text = AssistantNoticeText(
            format: "notification.weeklyDigest.body.simple",
            values: [.week(start: weekStart), .amount(week.expenses, currency: baseCurrency)]
        )
        var mood = AssistantNotice.Mood.idle
        if currentIndex > 1 {
            let before = weekPoints[currentIndex - 2]
            if before.expenses > 0 {
                let change = (week.expenses - before.expenses) / before.expenses * 100
                text = AssistantNoticeText(
                    format: "notification.weeklyDigest.body.withComparison",
                    values: [.week(start: weekStart), .amount(week.expenses, currency: baseCurrency), .text(String(format: "%+.0f%%", change))]
                )
                mood = change <= -5 ? .happy : (change >= 20 ? .concerned : .idle)
            }
        }
        return AssistantNotice(
            id: "digest:\(week.key)",
            kind: .digest,
            title: String(localized: "notification.weeklyDigest.title"),
            body: text.body ?? "",
            hiddenBody: text.hiddenBody,
            text: text,
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
            let text = AssistantNoticeText(
                format: "assistant.notice.charge",
                values: [.amount(NSDecimalNumber(decimal: series.amount).doubleValue, currency: series.currency)]
            )
            return AssistantNotice(
                id: "charge:\(series.id):\(FastDateParser.string(from: tomorrow))",
                kind: .charge,
                title: series.description,
                body: text.body ?? "",
                hiddenBody: text.hiddenBody,
                text: text,
                mood: .idle,
                question: String(format: String(localized: "assistant.notice.ask.charge"), series.description),
                insightId: nil,
                subjectId: series.id,
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
            let owedToMe = debt.direction == .owedToMe
            let text = AssistantNoticeText(
                format: owedToMe ? "assistant.notice.debt.owedToMe" : "assistant.notice.debt.iOwe",
                values: [.amount(debt.remaining, currency: debt.currency)]
            )
            return AssistantNotice(
                id: "debt:\(debt.id):\(FastDateParser.string(from: tomorrow))",
                kind: .debt,
                title: debt.person,
                body: text.body ?? "",
                hiddenBody: text.hiddenBody,
                text: text,
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
            let text = AssistantNoticeText(
                format: "assistant.notice.goal.behind",
                values: [.amount(monthly, currency: goal.currency), .day(deadline)]
            )
            return AssistantNotice(
                id: "goal:\(goal.id):\(month)",
                kind: .goal,
                title: goal.name,
                body: text.body ?? "",
                hiddenBody: text.hiddenBody,
                text: text,
                mood: .concerned,
                question: String(format: String(localized: "assistant.notice.ask.goal"), goal.name),
                insightId: nil,
                subjectId: goal.id,
                createdAt: now
            )
        }
    }

    /// Auto-capture not set up (docs/archive/plans/plan-ads-readiness.md B1): once, after the first entries,
    /// for someone who hid Home's auto-capture card (while the card shows, it asks).
    static func setupNudge(entries: Int, capturing: Bool, cardHidden: Bool, now: Date) -> AssistantNotice? {
        guard entries >= setupAfterEntries, !capturing, cardHidden else { return nil }
        return AssistantNotice(
            id: "setup:autoCapture",
            kind: .setup,
            title: String(localized: "home.autoCapture.title"),
            body: String(localized: "assistant.notice.setup"),
            mood: .idle,
            question: "",
            insightId: nil,
            createdAt: now
        )
    }

    /// Entries before the setup message.
    static let setupAfterEntries = 5

    /// Held assets whose valuation is out of date (AssetValuationMath.isStale): once a half-year
    /// each, until a new valuation.
    static func staleAssets(
        _ assets: [Asset],
        summary: (Asset) -> AssetValuationMath.Summary,
        now: Date,
        calendar: Calendar = .current
    ) -> [AssistantNotice] {
        let year = calendar.component(.year, from: now)
        let half = calendar.component(.month, from: now) <= 6 ? 1 : 2
        return assets.filter { AssetValuationMath.isStale($0, today: now, calendar: calendar) }.map { asset in
            let text = AssistantNoticeText(
                format: "assistant.notice.asset.stale",
                values: [.amount(summary(asset).value, currency: asset.currency), .day(AssetValuationMath.lastValuedOn(asset))]
            )
            return AssistantNotice(
                id: "asset:\(asset.id):\(year)-H\(half)",
                kind: .asset,
                title: asset.name,
                body: text.body ?? "",
                hiddenBody: text.hiddenBody,
                text: text,
                mood: .idle,
                question: "",
                insightId: nil,
                subjectId: asset.id,
                createdAt: now
            )
        }
    }

    /// Long loans no asset is bought with (plan-assets-roadmap 1.2, the owner's decision D7: once
    /// a loan, ever): annuities of three years or more still owed, which a flat or a car is
    /// usually bought with. Installments are left out (a phone in parts), and so is a loan any
    /// asset links, held or sold.
    static func loansWithoutAsset(_ accounts: [Account], assets: [Asset], now: Date) -> [AssistantNotice] {
        let linked = Set(assets.compactMap(\.linkedLoanAccountId))
        return accounts.compactMap { account in
            guard let loan = account.loanInfo, loan.loanType == .annuity, loan.termMonths >= loanAssetMinMonths,
                  loan.remainingPrincipal > 0, !linked.contains(account.id) else { return nil }
            return AssistantNotice(
                id: "loanAsset:\(account.id)",
                kind: .loanAsset,
                title: account.name,
                body: String(localized: "assistant.notice.loanAsset"),
                mood: .idle,
                question: "",
                insightId: nil,
                subjectId: account.id,
                createdAt: now
            )
        }
    }

    /// A loan this long or longer may have bought a flat or a car.
    static let loanAssetMinMonths = 36

    /// A goal younger than this is never behind.
    static let goalGraceDays: Double = 30
    /// How far below the time gone the saved share must fall.
    static let goalBehindShare = 0.2
}

extension AssistantNotices {
    /// What messages may still talk about: the active subscriptions, the open debts and the
    /// goals. A message about one that is gone (deleted, a subscription paused, a debt settled)
    /// would send the person to something that is not there.
    struct Subjects: Equatable {
        var subscriptions: Set<String>
        var debts: Set<String>
        var goals: Set<String>
        /// An automation has recorded a payment: the setup message has done its job.
        var capturing = false
        /// The held assets whose valuation is still out of date.
        var staleAssets: Set<String> = []
        /// The loans still without an asset.
        var loansWithoutAsset: Set<String> = []
        /// The feedback round open now (FeedbackAsk): an earlier round's message has had its
        /// time. nil keeps whatever is there.
        var feedbackRound: Int? = nil

        func contains(_ notice: AssistantNotice) -> Bool {
            switch notice.kind {
            case .charge:
                // Charges kept before `subjectId` was set carry the series in their key.
                let id = notice.subjectId ?? notice.id.split(separator: ":").dropFirst().first.map(String.init)
                return id.map(subscriptions.contains) ?? true
            case .debt: return notice.subjectId.map(debts.contains) ?? true
            case .goal: return notice.subjectId.map(goals.contains) ?? true
            case .setup: return !capturing
            case .asset: return notice.subjectId.map(staleAssets.contains) ?? true
            case .loanAsset: return notice.subjectId.map(loansWithoutAsset.contains) ?? true
            case .feedback: return feedbackRound.map { notice.id == FeedbackAsk.noticeID(round: $0) } ?? true
            case .signal, .digest: return true
            }
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

    /// Drops the messages about a subscription, a debt or a goal that is gone. Their keys stay
    /// posted, so they never come back.
    func drop(outside subjects: AssistantNotices.Subjects) {
        let kept = notices.filter(subjects.contains)
        guard kept.count != notices.count else { return }
        notices = kept
        save()
    }

    /// Settings › Formats changed: the kept messages, read or not, are written in the new
    /// formats, each from its OWN values (`text`), never from newer figures. A message without
    /// values (kept before they existed, or whose words they cannot write) takes the words of
    /// the fresh message with its key in `candidates` only when both are of the same day: a key
    /// that repeats on another day may carry other figures. Any other keeps its words.
    func rewriteTexts(from candidates: [AssistantNotice], calendar: Calendar = .current) {
        var fresh: [String: AssistantNotice] = [:]
        for candidate in candidates where fresh[candidate.id] == nil { fresh[candidate.id] = candidate }
        var rewritten = notices
        for index in rewritten.indices {
            let kept = rewritten[index]
            if let text = kept.text {
                guard let body = text.body else { continue }
                rewritten[index].body = body
                rewritten[index].hiddenBody = text.hiddenBody ?? kept.hiddenBody
            } else if let candidate = fresh[kept.id], calendar.isDate(candidate.createdAt, inSameDayAs: kept.createdAt) {
                rewritten[index].title = candidate.title
                rewritten[index].body = candidate.body
                rewritten[index].hiddenBody = candidate.hiddenBody
                rewritten[index].question = candidate.question
                rewritten[index].text = candidate.text
            }
        }
        guard rewritten != notices else { return }
        notices = rewritten
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
