//
//  AssistantInboxFormatsTests.swift
//  TenraTests
//
//  Ten's kept messages after a change in Settings › Formats (AssistantInbox.rewriteTexts): a
//  message keeps the values its words are written from, so it is written again in the new
//  marks and date style, read or not; an insight's message takes the fresh one with its key; a
//  message neither covers keeps its words.
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

    private static func signal(_ formattedValue: String) -> Insight {
        Insight(
            id: "over",
            type: .budgetOverspend,
            title: "Кафе: бюджет превышен",
            subtitle: "Кафе",
            metric: InsightMetric(value: 1_234.5, formattedValue: formattedValue, currency: "KZT", unit: nil),
            trend: nil,
            severity: .warning,
            category: .budget,
            detailData: nil
        )
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
        let signal = try #require(AssistantNotices.signals(from: [Self.signal("1.234,50 ₸")], now: Self.now).first)
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
        let freshSignal = try #require(AssistantNotices.signals(from: [Self.signal("₸1,234.50")], now: Self.now).first)
        inbox.rewriteTexts(from: [freshSignal])

        let byId = Dictionary(uniqueKeysWithValues: inbox.notices.map { ($0.id, $0) })
        let rewrittenCharge = try #require(byId[charge.id])
        #expect(rewrittenCharge.body.contains("₸1,234.5"), "\(rewrittenCharge.body)")
        #expect(rewrittenCharge.hiddenBody?.contains(Formatting.hiddenAmount(currency: "KZT")) == true)
        #expect(rewrittenCharge.isRead)
        #expect(rewrittenCharge.createdAt == charge.createdAt)

        let rewrittenDigest = try #require(byId[digest.id])
        #expect(rewrittenDigest.body.contains(DateFormatters.day(weekStart, includeYear: true, style: .iso)), "\(rewrittenDigest.body)")
        #expect(rewrittenDigest.body.contains("₸1,234.5"))

        #expect(byId[signal.id]?.body == freshSignal.body)
        #expect(byId[legacy.id]?.body == legacy.body)

        // Kept: a relaunch reads the new words.
        let again = AssistantInbox(defaults: store)
        #expect(again.notices.first { $0.id == charge.id }?.body == rewrittenCharge.body)
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
