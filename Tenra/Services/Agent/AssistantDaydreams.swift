//
//  AssistantDaydreams.swift
//  Tenra
//
//  What Ten daydreams of on its home (DesignKit 4.11's `CreatureAmbience(daydreams:)`, the
//  owner's choice of what is on the person's mind): the next payment in the coming 3 days (its
//  icon, or a card), the goal closest to done (its icon, or a target; a trophy for one reached
//  this week), spending that is rising (a chart going up), a debt due within a week (a
//  handshake), then a coffee, a star and a plane. Pictures only: no amount or name ever shows.
//

import SwiftUI
import UIKit

enum AssistantDaydreams {
    /// How far ahead a payment and a debt count, and how long a reached goal is celebrated.
    static let paymentWindow: TimeInterval = 3 * 24 * 3600
    static let debtWindow: TimeInterval = 7 * 24 * 3600
    static let reachedWindow: TimeInterval = 7 * 24 * 3600
    /// What Ten thinks of when nothing else is on its mind.
    static let neutral = ["cup.and.saucer.fill", "star.fill", "airplane"]

    struct Payment: Equatable {
        var icon: IconSource?
        var date: Date
    }

    struct Goal: Equatable {
        var icon: IconSource?
        /// 0…1 of the target.
        var progress: Double
        var reachedAt: Date?
    }

    /// The pictures, the person's own first. `exists` tells a symbol this system can draw.
    static func symbols(
        payments: [Payment],
        goals: [Goal],
        spendingRising: Bool,
        debtDueDates: [Date],
        now: Date,
        exists: (String) -> Bool = { UIImage(systemName: $0) != nil }
    ) -> [String] {
        var symbols: [String] = []
        func add(_ symbol: String, fallback: String) {
            let picked = exists(symbol) ? symbol : fallback
            if !symbols.contains(picked) { symbols.append(picked) }
        }

        let soon = payments
            .filter { $0.date >= now.addingTimeInterval(-3600) && $0.date <= now.addingTimeInterval(paymentWindow) }
            .min { $0.date < $1.date }
        if let soon {
            add(symbolName(soon.icon) ?? "creditcard.fill", fallback: "creditcard.fill")
        }

        if goals.contains(where: { ($0.reachedAt.map { now.timeIntervalSince($0) } ?? .infinity) <= reachedWindow }) {
            add("trophy.fill", fallback: "star.fill")
        } else if let closest = goals.filter({ $0.reachedAt == nil }).max(by: { $0.progress < $1.progress }) {
            add(symbolName(closest.icon) ?? SavingsGoal.defaultIconName, fallback: SavingsGoal.defaultIconName)
        }

        if spendingRising {
            add("chart.line.uptrend.xyaxis", fallback: "chart.bar.fill")
        }

        if debtDueDates.contains(where: { $0 <= now.addingTimeInterval(debtWindow) }) {
            add("handshake.fill", fallback: "banknote.fill")
        }

        for symbol in neutral where !symbols.contains(symbol) {
            symbols.append(symbol)
        }
        return symbols
    }

    /// An SF Symbol's name; nil for a brand logo, which Ten cannot draw in dots.
    private static func symbolName(_ icon: IconSource?) -> String? {
        if case .sfSymbol(let name) = icon { return name }
        return nil
    }
}

private extension SavingsGoal {
    /// The target a goal shows when the person picked no icon.
    static var defaultIconName: String {
        if case .sfSymbol(let name) = defaultIcon { return name }
        return "target"
    }
}
