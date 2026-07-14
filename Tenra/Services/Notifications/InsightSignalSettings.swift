//
//  InsightSignalSettings.swift
//  Tenra
//
//  Insights product audit 2026-07 — Phase C.
//  UserDefaults-backed preferences for insight signal notifications:
//  a master switch + one toggle per signal kind (benchmark rule: per-type
//  granularity raises opt-in and lowers uninstalls; a master-only switch
//  makes users kill everything).
//

import Foundation
import Observation

@MainActor
@Observable
final class InsightSignalSettings {
    static let shared = InsightSignalSettings()

    private static let masterKey = "insightSignals.enabled"
    private static func kindKey(_ kind: InsightSignalKind) -> String {
        "insightSignals.kind.\(kind.rawValue)"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Master switch. Defaults to ON — individual kinds are conservative
    /// (critical/warning transitions only, ≤5 pushes/week).
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.masterKey) }
    }

    /// Monday-09:00 weekly summary push (Phase D). Separate from the diff
    /// signals — it's a scheduled ritual, not a transition, and doesn't count
    /// against the weekly cap.
    var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Self.weeklyDigestKey) }
    }
    private static let weeklyDigestKey = "insightSignals.weeklyDigest"

    /// Per-kind toggles. Mutate through `setKind(_:enabled:)`.
    private(set) var enabledByKind: [InsightSignalKind: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = (defaults.object(forKey: Self.masterKey) as? Bool) ?? true
        self.weeklyDigestEnabled = (defaults.object(forKey: Self.weeklyDigestKey) as? Bool) ?? true
        var map: [InsightSignalKind: Bool] = [:]
        for kind in InsightSignalKind.allCases {
            map[kind] = (defaults.object(forKey: Self.kindKey(kind)) as? Bool) ?? true
        }
        self.enabledByKind = map
    }

    func isKindEnabled(_ kind: InsightSignalKind) -> Bool {
        enabledByKind[kind] ?? true
    }

    func setKind(_ kind: InsightSignalKind, enabled: Bool) {
        enabledByKind[kind] = enabled
        defaults.set(enabled, forKey: Self.kindKey(kind))
    }

    /// The effective set the signal service filters against — empty when the
    /// master switch is off.
    var enabledKinds: Set<InsightSignalKind> {
        guard isEnabled else { return [] }
        return Set(InsightSignalKind.allCases.filter { isKindEnabled($0) })
    }
}
