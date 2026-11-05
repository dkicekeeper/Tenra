//
//  AssistantInboxFormatsTests.swift
//  TenraTests
//
//  Ten's kept messages after a change in Settings › Formats (AssistantInbox.rewriteTexts): a
//  message keeps the values its words are written from, so it is written again in the new
//  marks and date style, read or not, insight messages included (their subtitle as words, the
//  value as an amount, the change as words); a message without values keeps its words.
//
//  `.sharedProcessState`: writes `FormatSettings.snapshot` and `AmountDisplayConfiguration.shared`,
//  and restores them.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite("AssistantInbox formats", .serialized, .sharedProcessState)
struct AssistantInboxFormatsTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
    }

    /// The formats in force: the snapshot the formatters read and DesignKit's amounts.
    private static func use(_ formats: FormatSettings, _ edit: (inout FormatChoices) -> Void) {
        formats.set(edit)
        DesignKitBridge.apply(formats.resolved)
    }

    /// A budget overspend of 1 234,5 ₸ written in the formats in force, its change `percent`.
    private static func signal(
        type: InsightType = .budgetOverspend,
        value: Double = 1_234.5,
        prefix: String = "",
        percent: Double? = nil,
        hiddenSubtitle: String? = nil
    ) -> Insight {
        var insight = Insight(
            id: "over",
            type: type,
            title: "Кафе: бюджет превышен",
            subtitle: "Кафе",
            metric: InsightMetric(value: value, formattedValue: prefix + Formatting.formatCurrencySmart(value, currency: "KZT"), currency: "KZT", unit: nil),
            trend: percent.map { InsightTrend(direction: .up, changePercent: $0, changeAbsolute: nil, comparisonPeriod: "") },
            severity: .warning,
            category: .budget,
            detailData: nil
        )
        insight.hiddenSubtitle = hiddenSubtitle
        return insight
    }

    private static func weeks() -> [PeriodDataPoint] {
        let current = InsightGranularity.week.currentPeriodKey
        let start = InsightGranularity.week.periodStart(for: current)
        return [-1, 0].map { offset in
            let begin = Calendar.current.date(byAdding: .day, value: 7 * offset, to: start)!
            let key = InsightGranularity.week.groupingKey(for: begin)
            return PeriodDataPoint(id: key, granularity: .week, key: key, periodStart: begin,
                                   periodEnd: Calendar.current.date(byAdding: .day, value: 7, to: begin)!,
                                   label: key, income: 0, expenses: 1_234.5, cumulativeBalance: nil)
        }
    }

    @Test func aFormatChangeWritesTheKeptMessagesAgain() throws {
        let savedAmounts = AmountDisplayConfiguration.shared
        defer {
            AmountDisplayConfiguration.shared = savedAmounts
            FormatSettings.resetSnapshot()
        }
        let formats = FormatSettings(defaults: Self.defaults())
        Self.use(formats) { $0.separators = .dotComma; $0.date = .words; $0.symbol = .after }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Self.now))!
        let netflix = RecurringSeries(amount: 1_234.5, currency: "KZT", category: "Subscriptions", description: "Netflix",
                                      frequency: .monthly, startDate: "2026-01-15", kind: .subscription, status: .active)
        let charge = try #require(AssistantNotices.charges(subscriptions: [netflix], nextCharge: { _ in tomorrow }, now: Self.now).first)
        let digest = try #require(AssistantNotices.digest(weekPoints: Self.weeks(), baseCurrency: "KZT", now: Self.now))
        let signal = try #require(AssistantNotices.signals(from: [Self.signal()], now: Self.now).first)
        // A message kept before its values were: only a fresh message with its key rewrites it.
        var legacy = charge
        legacy.id = "charge:old:2026-01-15"
        legacy.text = nil
        #expect(charge.body.contains("1.234,5"))
        let weekStart = Self.weeks()[0].periodStart
        let wordsDay = DateFormatters.day(weekStart, includeYear: true)
        #expect(digest.body.contains(wordsDay))

        let store = Self.defaults()
        let inbox = AssistantInbox(defaults: store)
        inbox.post([charge, digest, signal, legacy], now: Self.now)
        inbox.markRead(charge.id)

        Self.use(formats) { $0.separators = .commaDot; $0.date = .iso; $0.symbol = .before }
        inbox.rewriteTexts(from: [])

        let byId = Dictionary(uniqueKeysWithValues: inbox.notices.map { ($0.id, $0) })
        let rewrittenCharge = try #require(byId[charge.id])
        #expect(rewrittenCharge.body.contains("₸1,234.5"), "\(rewrittenCharge.body)")
        #expect(rewrittenCharge.hiddenBody?.contains(Formatting.hiddenAmount(currency: "KZT")) == true)
        #expect(rewrittenCharge.isRead)
        #expect(rewrittenCharge.createdAt == charge.createdAt)

        let rewrittenDigest = try #require(byId[digest.id])
        #expect(rewrittenDigest.body.contains(DateFormatters.day(weekStart, includeYear: true, style: .iso)), "\(rewrittenDigest.body)")
        #expect(rewrittenDigest.body.contains("₸1,234.5"))

        #expect(byId[signal.id]?.body.contains("₸1,234.5") == true, "\(byId[signal.id]?.body ?? "")")
        #expect(byId[legacy.id]?.body == legacy.body)

        // Kept: a relaunch reads the new words.
        let again = AssistantInbox(defaults: store)
        #expect(again.notices.first { $0.id == charge.id }?.body == rewrittenCharge.body)
    }

    /// An insight's message keeps its subtitle, its value and its change, and reads as the push
    /// does (InsightSignalService.notificationBody); a subtitle with an amount or a day in it
    /// (`hiddenSubtitle`, the large expense's date) keeps the message as written.
    @Test func aSignalMessageKeepsItsValues() throws {
        let savedAmounts = AmountDisplayConfiguration.shared
        defer {
            AmountDisplayConfiguration.shared = savedAmounts
            FormatSettings.resetSnapshot()
        }
        let formats = FormatSettings(defaults: Self.defaults())
        Self.use(formats) { $0.separators = .dotComma; $0.symbol = .after }

        let insight = Self.signal(percent: 25)
        let notice = try #require(AssistantNotices.signals(from: [insight], now: Self.now).first)
        #expect(notice.text != nil)
        #expect(notice.body == InsightSignalService.notificationBody(for: insight))
        #expect(notice.hiddenBody == InsightSignalService.hiddenNotificationBody(for: insight))
        // A value written with its "+" (the projected balance) keeps it.
        let growing = Self.signal(type: .projectedBalance, value: 500, prefix: "+")
        let growingNotice = try #require(AssistantNotices.signals(from: [growing], now: Self.now).first)
        #expect(growingNotice.text != nil)
        #expect(growingNotice.body == InsightSignalService.notificationBody(for: growing))

        let withAmount = Self.signal(hiddenSubtitle: "Кафе ••••")
        #expect(AssistantNotices.signals(from: [withAmount], now: Self.now).first?.text == nil)
        let large = Self.signal(type: .largeTransaction)
        #expect(AssistantNotices.signals(from: [large], now: Self.now).first?.text == nil)

        let inbox = AssistantInbox(defaults: Self.defaults())
        inbox.post([notice], now: Self.now)
        Self.use(formats) { $0.separators = .commaDot }
        inbox.rewriteTexts(from: [])
        let rewritten = try #require(inbox.notices.first)
        #expect(rewritten.body.contains("1,234.50"), "\(rewritten.body)")
        #expect(rewritten.body.contains("(+25%)"))
        #expect(rewritten.body.hasPrefix("Кафе · "))
    }

    /// A message kept before the values existed decodes without them.
    @Test func aMessageKeptBeforeItsValuesStillDecodes() throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Self.now))!
        let netflix = RecurringSeries(amount: 4990, currency: "KZT", category: "Subscriptions", description: "Netflix",
                                      frequency: .monthly, startDate: "2026-01-15", kind: .subscription, status: .active)
        let charge = try #require(AssistantNotices.charges(subscriptions: [netflix], nextCharge: { _ in tomorrow }, now: Self.now).first)
        #expect(charge.text != nil)
        var kept = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(charge)) as? [String: Any])
        kept["text"] = nil
        let decoded = try JSONDecoder().decode(AssistantNotice.self, from: JSONSerialization.data(withJSONObject: kept))
        #expect(decoded.text == nil)
        #expect(decoded.body == charge.body)
    }
}
