//
//  AssistantRegion.swift
//  Tenra
//
//  Whether the cloud answers in this country (docs/domains/assistant.md §10). The server refuses
//  Russia and Belarus (451) by the request's country, since the Anthropic API does not serve
//  them. Learned from that answer and kept on the phone: there Ten says once that it cannot
//  answer questions, stops inviting them and keeps recording expenses on the phone (FastPath).
//  Checked again after a week, in case the person is somewhere the cloud answers.
//

import Foundation

nonisolated struct AssistantRegion {
    /// When the server last answered 451, seconds since 1970; 0 when it never did or answered
    /// since. Read by `@AppStorage` in the views that stop inviting questions.
    static let outOfRegionKey = "assistant.region.outOfRegionAt"
    /// Ten has said once that it cannot answer questions here. Kept for good.
    static let explainedKey = "assistant.region.explained"
    /// After this a question goes to the server again.
    static let recheckAfter: TimeInterval = 7 * 86_400

    var defaults: UserDefaults = .standard

    /// The rule, pure: `markedAt` is the stored value of `outOfRegionKey`.
    static func isOutOfRegion(markedAt: Double, now: Date) -> Bool {
        guard markedAt > 0 else { return false }
        return now.timeIntervalSince1970 - markedAt < recheckAfter
    }

    func isOutOfRegion(now: Date) -> Bool {
        Self.isOutOfRegion(markedAt: defaults.double(forKey: Self.outOfRegionKey), now: now)
    }

    /// The server answered 451. True the first time ever: Ten explains it then, and never again.
    @discardableResult
    func markOutOfRegion(now: Date) -> Bool {
        defaults.set(now.timeIntervalSince1970, forKey: Self.outOfRegionKey)
        guard !defaults.bool(forKey: Self.explainedKey) else { return false }
        defaults.set(true, forKey: Self.explainedKey)
        return true
    }

    /// The model answered: the cloud serves this country (again).
    func markServed() {
        guard defaults.double(forKey: Self.outOfRegionKey) > 0 else { return }
        defaults.removeObject(forKey: Self.outOfRegionKey)
    }
}
