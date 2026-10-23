//
//  WidgetSnapshot.swift
//  Tenra
//
//  What the widgets and the Control Center button show, written by the app into the App Group
//  container as one small JSON file (the CoreData store stays the app's: docs/domains/intents.md
//  §8). The widget extension reads the same file with its own copy of the type
//  (TenraWidgets/WidgetData.swift): keep the keys in step, WidgetSnapshotTests pins them.
//

import Foundation
import WidgetKit

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// A category the medium widget offers for a quick expense.
    nonisolated struct Category: Codable, Equatable, Sendable {
        let name: String
        /// An SF Symbol; a category with a brand logo shows a generic one.
        let symbol: String
        let colorHex: String
    }

    var version = 1
    /// The day (`yyyy-MM-dd`) the figures are for; the widget shows 0 spent on another day.
    var day: String
    var currency: String
    /// "Hide amounts" is on: the widget shows dots.
    var amountsHidden: Bool
    /// For today (DailyAllowance); nil without an everyday account.
    var allowance: Double?
    /// The income the allowance runs to (`yyyy-MM-dd`); nil for the month's end.
    var incomeDay: String?
    /// Realized expenses today, in `currency` (the summary rule, SummaryContribution).
    var spentToday: Double
    /// The most used expense categories of the last 30 days, at most four.
    var categories: [Category]
}

enum WidgetSnapshotStore {
    /// Shared by the app and TenraWidgets (both entitlements).
    nonisolated static let appGroup = "group.dakacom.Tenra"
    nonisolated static let fileName = "widget-snapshot.json"

    nonisolated static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    /// Writes the snapshot and asks the widgets to redraw, only when it changed.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        if let current = try? Data(contentsOf: url), current == data { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// Builds the snapshot from the app's data: when the app goes to the background and after the
/// full load (TenraApp, ContentView).
enum WidgetSnapshotBuilder {
    /// Categories the medium widget offers.
    static let categoryLimit = 4

    static func build(coordinator: AppCoordinator, now: Date = Date()) async -> WidgetSnapshot {
        let store = coordinator.transactionStore
        let amountsHidden = coordinator.transactionsViewModel.appSettings.hidesAmounts
        let base = store.baseCurrency
        let today = FastDateParser.string(from: now)
        let allowance = await DailyAllowance.value(store: store, now: now)

        // Today's spending and the categories used most lately, off the main actor.
        let transactions = store.transactions
        let rates = RateSnapshot()
        let monthAgo = FastDateParser.string(from: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now)
        let (spent, usage) = await Task.detached(priority: .utility) { () -> (Double, [String: Int]) in
            var spent = 0.0
            var usage: [String: Int] = [:]
            for transaction in transactions where transaction.date <= today {
                guard transaction.type.summaryContribution(isFuture: false) == .expense else { continue }
                if transaction.date == today {
                    spent += rates.convert(transaction.amount, from: transaction.currency, to: base)
                        ?? (transaction.currency == base ? transaction.amount : 0)
                }
                if transaction.type == .expense, transaction.date >= monthAgo, !transaction.category.isEmpty {
                    usage[transaction.category, default: 0] += 1
                }
            }
            return (spent, usage)
        }.value

        let expenseCategories = store.categories.filter { $0.type == .expense }
        let ranked = expenseCategories
            .enumerated()
            .sorted { lhs, rhs in
                let left = usage[lhs.element.name] ?? 0, right = usage[rhs.element.name] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .prefix(categoryLimit)
            .map { entry -> WidgetSnapshot.Category in
                let symbol: String
                if case .sfSymbol(let name) = entry.element.iconSource { symbol = name } else { symbol = "tag.fill" }
                return WidgetSnapshot.Category(name: entry.element.name, symbol: symbol, colorHex: entry.element.colorHex)
            }

        return WidgetSnapshot(
            day: today,
            currency: base,
            amountsHidden: amountsHidden,
            allowance: allowance?.amount,
            incomeDay: allowance?.income.map { FastDateParser.string(from: $0) },
            spentToday: spent,
            categories: Array(ranked)
        )
    }

    /// Builds and writes the snapshot.
    static func refresh(coordinator: AppCoordinator) async {
        guard coordinator.isFullyInitialized else { return }
        WidgetSnapshotStore.write(await build(coordinator: coordinator))
    }
}
