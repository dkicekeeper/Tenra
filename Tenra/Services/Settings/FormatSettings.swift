//
//  FormatSettings.swift
//  Tenra
//
//  The store of the person's format choices. `resolved` is what the app writes dates and
//  amounts with; `version` grows only when it changes, so caches of formatted text key on it.
//

import Foundation
import Observation

@MainActor
@Observable
final class FormatSettings {

    nonisolated static let storageKey = "settings.formats"

    private(set) var choices: FormatChoices
    private(set) var resolved: ResolvedFormats
    private(set) var version = 0
    @ObservationIgnored var onChange: ((ResolvedFormats) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: () -> Locale
    @ObservationIgnored private var observer: NSObjectProtocol?

    var isCustomized: Bool {
        !FormatPreferences.isEquivalent(resolved, FormatPreferences.region(for: locale()))
    }

    init(defaults: UserDefaults, locale: @escaping () -> Locale = { .current }) {
        self.defaults = defaults
        self.locale = locale
        let stored = Self.storedChoices(in: defaults)
        choices = stored
        resolved = FormatPreferences.resolve(stored, locale: locale())
        Self.publish(resolved)
        observer = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.regionDidChange() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func set(_ edit: (inout FormatChoices) -> Void) {
        var edited = choices
        edit(&edited)
        guard edited != choices else { return }
        choices = edited
        if let data = try? JSONEncoder().encode(edited) {
            defaults.set(data, forKey: Self.storageKey)
        }
        refresh()
    }

    func resetToRegion() {
        set { $0 = FormatChoices() }
    }

    /// The phone's region or language changed: resolve again.
    func regionDidChange() {
        refresh()
    }

    private func refresh() {
        let next = FormatPreferences.resolve(choices, locale: locale())
        guard next != resolved else { return }
        resolved = next
        version += 1
        Self.publish(next)
        onChange?(next)
    }

    // MARK: - Snapshot

    /// The resolved formats for code off the main actor and for code that runs before any
    /// instance exists (`DesignKitBridge.configure()`): it then reads the stored choices from
    /// the App Group itself.
    nonisolated static var snapshot: ResolvedFormats {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        if let value = snapshotValue { return value }
        let defaults = snapshotDefaults ?? UserDefaults(suiteName: WidgetSnapshotStore.appGroup) ?? .standard
        let value = FormatPreferences.resolve(storedChoices(in: defaults), locale: .current)
        snapshotValue = value
        return value
    }

    private nonisolated(unsafe) static var snapshotDefaults: UserDefaults?

    /// Test hook: drops the cached snapshot so the next read resolves from the stored choices
    /// again (from `defaults` when given, else the App Group).
    nonisolated static func resetSnapshot(defaults: UserDefaults? = nil) {
        snapshotLock.lock()
        snapshotValue = nil
        snapshotDefaults = defaults
        snapshotLock.unlock()
    }

    private nonisolated static let snapshotLock = NSLock()
    private nonisolated(unsafe) static var snapshotValue: ResolvedFormats?

    private nonisolated static func publish(_ value: ResolvedFormats) {
        snapshotLock.lock()
        snapshotValue = value
        snapshotLock.unlock()
    }

    private nonisolated static func storedChoices(in defaults: UserDefaults) -> FormatChoices {
        guard let data = defaults.data(forKey: storageKey),
              let choices = try? JSONDecoder().decode(FormatChoices.self, from: data) else {
            return FormatChoices()
        }
        return choices
    }
}
