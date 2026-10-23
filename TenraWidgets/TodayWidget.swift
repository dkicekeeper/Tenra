//
//  TodayWidget.swift
//  TenraWidgets
//
//  "For today": how much can go out a day until the next income (the app's DailyAllowance,
//  the same number as on Home and in Ten's forecast) and what went out today. Small: the
//  figure, a tap opens the assistant (tenra://add). Medium: the four most used expense
//  categories beside it, a tap opens the add form for one (tenra://add?category=). Lock Screen:
//  the figure. The app writes the data (WidgetSnapshotStore) when it goes to the background
//  and after a load; the timeline redraws after midnight, when "spent today" starts at zero.
//

import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), data: context.isPreview ? .placeholder : WidgetData.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let entries = [
            TodayEntry(date: now, data: WidgetData.load()),
            TodayEntry(date: nextDay, data: WidgetData.load()),
        ]
        completion(Timeline(entries: entries, policy: .after(nextDay)))
    }
}

struct TodayWidget: Widget {
    static let kind = "dakacom.Tenra.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.today.name"))
        .description(String(localized: "widget.today.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let data = entry.data {
            switch family {
            case .systemMedium:
                HStack(spacing: 12) {
                    summary(data)
                    categories(data)
                }
                .widgetURL(Self.addURL(category: nil))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "widget.today.title"))
                        .font(.caption2)
                        .widgetAccentable()
                    Text(allowance(data))
                        .font(.headline)
                        .minimumScaleFactor(0.6)
                    Text(data.horizonLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(Self.addURL(category: nil))
            case .accessoryInline:
                Text(String(format: String(localized: "widget.today.inline"), allowance(data)))
                    .widgetURL(Self.addURL(category: nil))
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "sun.max.fill")
                            .font(.caption)
                            .widgetAccentable()
                        Text(allowance(data))
                            .font(.caption2.weight(.semibold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .padding(4)
                }
                .widgetURL(Self.addURL(category: nil))
            default:
                summary(data)
                    .widgetURL(Self.addURL(category: nil))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "widget.today.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(Self.addURL(category: nil))
        }
    }

    private func allowance(_ data: WidgetData) -> String {
        data.allowance.map { data.money($0) } ?? "–"
    }

    private func summary(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "widget.today.title"), systemImage: "sun.max.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Spacer(minLength: 0)
            Text(allowance(data))
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(data.horizonLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(String(format: String(localized: "widget.today.spent"), data.money(data.spent(on: entry.date))))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func categories(_ data: WidgetData) -> some View {
        let shown = Array(data.categories.prefix(4))
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        if index < shown.count {
                            categoryButton(shown[index])
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryButton(_ category: WidgetData.Category) -> some View {
        Link(destination: Self.addURL(category: category.name)) {
            VStack(spacing: 4) {
                Image(systemName: category.symbol)
                    .font(.body)
                    .foregroundStyle(Color(widgetHex: category.colorHex))
                    .frame(width: 36, height: 36)
                    .background(Color(widgetHex: category.colorHex).opacity(0.15), in: Circle())
                Text(category.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// tenra://add opens the assistant (or Home); with a category, its add form.
    static func addURL(category: String?) -> URL {
        var components = URLComponents()
        components.scheme = "tenra"
        components.host = "add"
        if let category { components.queryItems = [URLQueryItem(name: "category", value: category)] }
        return components.url ?? URL(string: "tenra://add")!
    }
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: Date(), data: .placeholder)
}
