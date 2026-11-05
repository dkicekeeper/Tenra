//
//  FormatSettingsTests.swift
//  TenraTests
//
//  Pins the store of format choices: persistence, versioning, reset and the shared snapshot.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.sharedProcessState)
final class FormatSettingsTests {

    /// Every test leaves the process-wide snapshot as it found it (resolved afresh on next read).
    deinit { FormatSettings.resetSnapshot() }

    private func makeDefaults() -> UserDefaults {
        let name = "FormatSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let kazakhstan: () -> Locale = { Locale(identifier: "ru_KZ") }

    @Test("A new instance reads the saved choices")
    func persistsChoices() {
        let defaults = makeDefaults()
        let first = FormatSettings(defaults: defaults, locale: kazakhstan)
        first.set { $0.separators = .commaDot; $0.firstWeekday = 1 }
        let second = FormatSettings(defaults: defaults, locale: kazakhstan)
        #expect(second.choices.separators == .commaDot)
        #expect(second.choices.firstWeekday == 1)
        #expect(second.resolved.decimalSeparator == ".")
    }

    @Test("Setting the same value again does not raise the version")
    func versionBumpsOnlyOnChange() {
        let settings = FormatSettings(defaults: makeDefaults(), locale: kazakhstan)
        let start = settings.version
        settings.set { $0.separators = .commaDot }
        #expect(settings.version == start + 1)
        settings.set { $0.separators = .commaDot }
        #expect(settings.version == start + 1)
    }

    @Test("Customized after a choice, back to the region after a reset")
    func customizedAndReset() {
        let settings = FormatSettings(defaults: makeDefaults(), locale: kazakhstan)
        #expect(!settings.isCustomized)
        settings.set { $0.separators = .commaDot }
        #expect(settings.isCustomized)
        settings.resetToRegion()
        #expect(!settings.isCustomized)
        #expect(settings.choices == FormatChoices())
    }

    @Test("The shared snapshot follows every change")
    func snapshotFollows() {
        let settings = FormatSettings(defaults: makeDefaults(), locale: kazakhstan)
        settings.set { $0.separators = .dotComma }
        #expect(FormatSettings.snapshot == settings.resolved)
        settings.set { $0.cents = .never }
        #expect(FormatSettings.snapshot == settings.resolved)
    }

    @Test("The calendar starts its week on the chosen day")
    func appCalendarUsesWeekStart() {
        let settings = FormatSettings(defaults: makeDefaults(), locale: kazakhstan)
        settings.set { $0.firstWeekday = 1 }
        #expect(AppCalendar.current.firstWeekday == 1)
        settings.set { $0.firstWeekday = 2 }
        #expect(AppCalendar.current.firstWeekday == 2)
    }

    @Test("A region change re-resolves and notifies only when the result changes")
    func regionDidChangeNotifies() {
        var current = Locale(identifier: "ru_KZ")
        let settings = FormatSettings(defaults: makeDefaults(), locale: { current })
        var notified = 0
        settings.onChange = { _ in notified += 1 }
        settings.regionDidChange()
        #expect(notified == 0)
        current = Locale(identifier: "en_US")
        let before = settings.version
        settings.regionDidChange()
        #expect(notified == 1)
        #expect(settings.version == before + 1)
        #expect(settings.resolved.decimalSeparator == ".")
    }

    @Test("In France a no-break space instead of the narrow one is not a customization")
    func franceSpaceIsNotCustomized() {
        let settings = FormatSettings(defaults: makeDefaults(), locale: { Locale(identifier: "fr_FR") })
        settings.set { $0.separators = .spaceComma }
        #expect(!settings.isCustomized)
    }

    @Test("Before any instance the snapshot reads the stored choices itself")
    func firstAccessReadsStoredChoices() throws {
        let defaults = makeDefaults()
        let choices = FormatChoices(separators: .dotComma, cents: .always)
        defaults.set(try JSONEncoder().encode(choices), forKey: FormatSettings.storageKey)
        FormatSettings.resetSnapshot(defaults: defaults)
        #expect(FormatSettings.snapshot == FormatPreferences.resolve(choices, locale: .current))
    }
}
