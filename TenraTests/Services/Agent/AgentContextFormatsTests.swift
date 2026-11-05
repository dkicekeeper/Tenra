//
//  AgentContextFormatsTests.swift
//  TenraTests
//
//  Ten's <app_context> carries the person's date format and first weekday (Settings › Formats).
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.sharedProcessState)
struct AgentContextFormatsTests {

    private func context() throws -> String {
        let snapshot = AgentContextSnapshot(
            today: Date(timeIntervalSince1970: 1_793_170_800),
            timeZone: try #require(TimeZone(identifier: "Asia/Almaty")),
            locale: "ru", baseCurrency: "KZT", accounts: [], categories: []
        )
        return AgentContextBuilder.text(for: snapshot)
    }

    private func text(_ choices: (inout FormatChoices) -> Void) throws -> String {
        let name = "AgentContextFormatsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = FormatSettings(defaults: defaults, locale: { Locale(identifier: "ru_KZ") })
        settings.set(choices)
        defer { FormatSettings.resetSnapshot() }
        return try context()
    }

    @Test func dotsStyleWritesTheSampleDateWithDots() throws {
        let text = try text { $0.date = .dots }
        #expect(text.contains("\ndate_format: 03.11.2026\n"))
    }

    @Test func isoAndSlashSamples() throws {
        let iso = try text { $0.date = .iso }
        let slash = try text { $0.date = .slash }
        #expect(iso.contains("date_format: 2026-11-03"))
        #expect(slash.contains("date_format: 11/03/2026"))
    }

    @Test func sundayFirstWeekIsNamed() throws {
        let sunday = try text { $0.firstWeekday = 1 }
        let monday = try text { $0.firstWeekday = 2 }
        #expect(sunday.contains("\nweek_starts: Sunday\n"))
        #expect(monday.contains("\nweek_starts: Monday\n"))
    }
}
