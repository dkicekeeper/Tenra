//
//  IntentUsageCounters.swift
//  Tenra
//
//  Local-only usage counters. The app ships with App Privacy set to "Data Not
//  Collected" and has no analytics SDK, so this is the only way to see whether
//  intents are actually being used. Nothing leaves the device; the numbers are
//  read in ExperimentsListView.
//
//  The ratio that matters is fallbacks / (intentAdds + fallbacks): it is the
//  health metric for the parser. A rising share means phrases are failing to
//  resolve and users are being bounced into the app.
//

import Foundation

final class IntentUsageCounters: @unchecked Sendable {

    static let shared = IntentUsageCounters()

    enum Event: String {
        case intentAdd = "intent.usage.intentAdds"
        case manualAdd = "intent.usage.manualAdds"
        case intentFallbackToApp = "intent.usage.fallbacks"
    }

    struct Snapshot {
        let intentAdds: Int
        let manualAdds: Int
        let fallbacks: Int
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ event: Event) {
        defaults.set(defaults.integer(forKey: event.rawValue) + 1, forKey: event.rawValue)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            intentAdds: defaults.integer(forKey: Event.intentAdd.rawValue),
            manualAdds: defaults.integer(forKey: Event.manualAdd.rawValue),
            fallbacks: defaults.integer(forKey: Event.intentFallbackToApp.rawValue)
        )
    }

    func reset() {
        for event in [Event.intentAdd, .manualAdd, .intentFallbackToApp] {
            defaults.removeObject(forKey: event.rawValue)
        }
    }
}
