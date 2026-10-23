//
//  WidgetData.swift
//  TenraWidgets
//
//  What the app wrote for the widgets: the App Group's widget-snapshot.json, the app's
//  WidgetSnapshot (Tenra/Services/Widgets/WidgetSnapshot.swift). This is the extension's copy
//  of that type: keep the keys in step (WidgetSnapshotTests pins them on the app side).
//

import Foundation
import SwiftUI

struct WidgetData: Codable, Equatable {
    struct Category: Codable, Equatable {
        let name: String
        let symbol: String
        let colorHex: String
    }

    var version: Int
    var day: String
    var currency: String
    var amountsHidden: Bool
    var allowance: Double?
    var incomeDay: String?
    var spentToday: Double
    var categories: [Category]

    static let appGroup = "group.dakacom.Tenra"
    static let fileName = "widget-snapshot.json"

    /// The app's last snapshot; nil before the app has written one.
    static func load() -> WidgetData? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    /// The gallery's sample.
    static let placeholder = WidgetData(
        version: 1,
        day: dayKey(Date()),
        currency: "KZT",
        amountsHidden: false,
        allowance: 8_400,
        incomeDay: nil,
        spentToday: 3_200,
        categories: [
            Category(name: String(localized: "widget.sample.food"), symbol: "fork.knife", colorHex: "#FF9500"),
            Category(name: String(localized: "widget.sample.transport"), symbol: "car.fill", colorHex: "#007AFF"),
            Category(name: String(localized: "widget.sample.coffee"), symbol: "cup.and.saucer.fill", colorHex: "#A2845E"),
            Category(name: String(localized: "widget.sample.shopping"), symbol: "bag.fill", colorHex: "#AF52DE"),
        ]
    )

    // MARK: - Reading

    /// What was spent today: nothing yet when the snapshot is from another day.
    func spent(on date: Date) -> Double {
        day == Self.dayKey(date) ? spentToday : 0
    }

    /// "a day until 25 Oct" or "a day until the month's end".
    var horizonLine: String {
        if let incomeDay, let date = Self.date(incomeDay) {
            return String(format: String(localized: "widget.today.untilIncome"),
                          date.formatted(.dateTime.day().month(.abbreviated)))
        }
        return String(localized: "widget.today.untilMonthEnd")
    }

    func money(_ amount: Double) -> String {
        if amountsHidden { return "•••" }
        return amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(amount.rounded() == amount || abs(amount) >= 100 ? 0 : 2))
                .presentation(.narrow)
        )
    }

    // MARK: - Dates (yyyy-MM-dd, as the app stores them)

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
}

extension Color {
    /// A category's stored colour (`#RRGGBB`); the accent when it does not parse.
    init(widgetHex hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .accentColor
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
