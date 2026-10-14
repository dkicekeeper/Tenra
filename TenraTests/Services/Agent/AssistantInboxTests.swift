//
//  AssistantInboxTests.swift
//  TenraTests
//
//  Ten writes first (AssistantInbox): critical and warning insights, last week's summary and
//  tomorrow's subscription charges become messages; a key never posts twice, insight messages
//  stop at two a day, reading one marks it, and "Go through it" asks its question with the
//  message for the model.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantInboxTests {

    private static func insight(_ id: String, severity: InsightSeverity, type: InsightType = .budgetOverspend, signalKey: String? = nil) -> Insight {
        Insight(
            id: id,
            type: type,
            title: "Кафе: бюджет превышен",
            subtitle: "Кафе",
            metric: InsightMetric(value: 100, formattedValue: "100 ₸", currency: "KZT", unit: nil),
            trend: nil,
            severity: severity,
            category: .budget,
            detailData: nil,
            signalKey: signalKey
        )
    }

    private static func inbox() -> AssistantInbox {
        AssistantInbox(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func criticalAndWarningInsightsBecomeMessagesWorstFirst() {
        let notices = AssistantNotices.signals(from: [
            Self.insight("warn", severity: .warning),
            Self.insight("calm", severity: .neutral),
            Self.insight("crit", severity: .critical),
            Self.insight("price", severity: .warning, type: .subscriptionPriceIncrease, signalKey: "netflix:5990"),
        ], now: Self.now)

        #expect(notices.map(\.id) == ["signal:crit", "signal:netflix:5990", "signal:warn"])
        #expect(notices.allSatisfy { $0.kind == .signal && $0.mood == .concerned })
        #expect(notices.first?.insightId == "crit")
        #expect(notices.first?.question == String(format: String(localized: "assistant.notice.ask"), "Кафе: бюджет превышен"))
    }

    @Test func aKeyNeverPostsTwiceAndSignalsStopAtTwoADay() {
        let inbox = Self.inbox()
        let signals = AssistantNotices.signals(from: [
            Self.insight("a", severity: .critical),
            Self.insight("b", severity: .critical),
            Self.insight("c", severity: .warning),
        ], now: Self.now)

        inbox.post(signals, now: Self.now)
        #expect(inbox.unread.map(\.id) == ["signal:b", "signal:a"])

        // Again the same day: nothing new, and the third waits for tomorrow.
        inbox.post(signals, now: Self.now.addingTimeInterval(3600))
        #expect(inbox.notices.count == 2)
        inbox.post(signals, now: Self.now.addingTimeInterval(86_400))
        #expect(inbox.notices.map(\.id) == ["signal:c", "signal:b", "signal:a"])

        // Read one: still kept, no longer unread, never posted again.
        inbox.markRead("signal:a")
        #expect(inbox.unread.map(\.id) == ["signal:c", "signal:b"])
        inbox.post(signals, now: Self.now.addingTimeInterval(3 * 86_400))
        #expect(inbox.notices.count == 3)
    }

    @Test func theInboxComesBackAfterARelaunch() {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let first = AssistantInbox(defaults: defaults)
        first.post(AssistantNotices.signals(from: [Self.insight("a", severity: .critical)], now: Self.now), now: Self.now)
        first.markRead("signal:a")

        let again = AssistantInbox(defaults: defaults)
        #expect(again.notices.map(\.id) == ["signal:a"])
        #expect(again.unread.isEmpty)
        again.post(AssistantNotices.signals(from: [Self.insight("a", severity: .critical)], now: Self.now), now: Self.now.addingTimeInterval(86_400))
        #expect(again.notices.count == 1)
    }

    @Test func lastWeekIsSummedUpAgainstTheWeekBefore() throws {
        let current = InsightGranularity.week.currentPeriodKey
        let start = InsightGranularity.week.periodStart(for: current)
        func week(_ offset: Int, _ expenses: Double) -> PeriodDataPoint {
            let begin = Calendar.current.date(byAdding: .day, value: 7 * offset, to: start)!
            let key = InsightGranularity.week.groupingKey(for: begin)
            return PeriodDataPoint(id: key, granularity: .week, key: key, periodStart: begin,
                                   periodEnd: Calendar.current.date(byAdding: .day, value: 7, to: begin)!,
                                   label: key, income: 0, expenses: expenses, cumulativeBalance: nil)
        }

        let points = [week(-2, 100_000), week(-1, 80_000), week(0, 5_000)]
        let digest = try #require(AssistantNotices.digest(weekPoints: points, baseCurrency: "KZT", now: Self.now))
        #expect(digest.id == "digest:\(points[1].key)")
        #expect(digest.kind == .digest)
        #expect(digest.mood == .happy)
        #expect(digest.body.contains("-20%"))

        // A week with nothing spent says nothing.
        #expect(AssistantNotices.digest(weekPoints: [week(-1, 0), week(0, 5_000)], baseCurrency: "KZT", now: Self.now) == nil)
        // No week before the current one yet.
        #expect(AssistantNotices.digest(weekPoints: [week(0, 5_000)], baseCurrency: "KZT", now: Self.now) == nil)
    }

    @Test func aSubscriptionChargedTomorrowIsAMessage() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Self.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let netflix = RecurringSeries(amount: 4990, currency: "KZT", category: "Subscriptions", description: "Netflix",
                                      frequency: .monthly, startDate: "2026-01-15", kind: .subscription, status: .active)
        let spotify = RecurringSeries(amount: 2990, currency: "KZT", category: "Subscriptions", description: "Spotify",
                                      frequency: .monthly, startDate: "2026-01-20", kind: .subscription, status: .active)

        let notices = AssistantNotices.charges(
            subscriptions: [netflix, spotify],
            nextCharge: { $0.id == netflix.id ? tomorrow : calendar.date(byAdding: .day, value: 5, to: today) },
            now: Self.now
        )

        #expect(notices.map(\.title) == ["Netflix"])
        #expect(notices.first?.id == "charge:\(netflix.id):\(FastDateParser.string(from: tomorrow))")
        #expect(notices.first?.question == String(format: String(localized: "assistant.notice.ask.charge"), "Netflix"))
    }

    @Test func goingThroughAMessageAsksItsQuestionWithTheMessage() async {
        let transport = ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_1", source: "none")])]])
        let model = AssistantViewModel(conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()), context: { "<app_context>a</app_context>" })
        let notice = AssistantNotices.signals(from: [Self.insight("crit", severity: .critical)], now: Self.now)[0]

        #expect(await model.ask(about: notice))

        let texts = transport.calls.first?.last?.content.compactMap { $0["text"]?.stringValue } ?? []
        #expect(texts == ["<app_context>a</app_context>", notice.modelText, notice.question])
        #expect(notice.modelText.contains("\"insight_id\":\"crit\""))
        // Without the cloud nothing goes.
        #expect(await model.ask(about: notice, cloudAllowed: false) == false)
    }
}
