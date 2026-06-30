//
//  SubscriptionCalendarView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

private struct CalendarDay: Identifiable {
    let id: String
    let date: Date?
}

/// Pure date logic for the subscription calendar's week/month toggle. Extracted so the
/// collapse anchoring is unit-testable (the view's @State indices are not).
enum SubscriptionCalendarSync {
    /// Week index to show when collapsing month → week.
    ///
    /// Keeps the currently-shown week when it already falls inside the displayed month, so
    /// expand→collapse on the same month is a no-op and preserves today's week. Only when the
    /// user swiped to a *different* month while expanded does it re-anchor — to the week
    /// containing today if that month is the current month, otherwise the month's first day.
    ///
    /// Previously this always snapped to the month's first-day week, so collapsing the current
    /// month jumped "29 июня–5 июля" → "1 июня–7 июня".
    static func collapsedWeekIndex(
        displayedMonth: Date,
        currentWeekIndex: Int,
        weeks: [Date],
        today: Date,
        calendar: Calendar
    ) -> Int {
        guard weeks.indices.contains(currentWeekIndex) else { return currentWeekIndex }

        let currentWeekStart = weeks[currentWeekIndex]
        if calendar.isDate(currentWeekStart, equalTo: displayedMonth, toGranularity: .month) {
            return currentWeekIndex
        }

        let anchor = calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
            ? calendar.startOfDay(for: today)
            : displayedMonth
        let idx = weeks.firstIndex { weekStart in
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return false }
            return weekStart <= anchor && anchor < weekEnd
        }
        return idx ?? currentWeekIndex
    }
}

struct SubscriptionCalendarView: View {
    let subscriptions: [RecurringSeries]
    let baseCurrency: String

    @State private var isExpanded = false
    @State private var currentMonthIndex: Int = 0
    @State private var currentWeekIndex: Int = 8 // weeksBefore = 8, index 8 = current week
    @State private var monthlyTotals: [Int: Decimal] = [:]
    @State private var weeklyTotals: [Int: Decimal] = [:]
    /// Pre-computed: subscriptions keyed by day-of-month string "YYYY-M-D"
    @State private var subscriptionsByDay: [String: [RecurringSeries]] = [:]
    /// Cached date arrays — avoid recomputing on every body evaluation
    @State private var cachedMonths: [Date] = []
    @State private var cachedWeeks: [Date] = []

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = .current
        f.timeZone = TimeZone.current
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = .current
        return f
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header
            weekdayHeaderRow
            calendarContent
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .onAppear {
            cachedMonths = computeAllMonths()
            cachedWeeks = computeAllWeeks()
            rebuildSubscriptionsByDay()
        }
        .task {
            await refreshTotals()
        }
        .onChange(of: subscriptions.count) { _, _ in
            rebuildSubscriptionsByDay()
            Task { await refreshTotals() }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task { await refreshTotals() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Group {
                if isExpanded {
                    Button(action: {
                        withAnimation(AppAnimation.contentSpring) {
                            currentMonthIndex = 0
                        }
                    }) {
                        Text(formatMonthYear(cachedMonths.isEmpty ? Date() : cachedMonths[currentMonthIndex]))
                            .font(AppTypography.h4)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(formatWeekRange(cachedWeeks.isEmpty ? Date() : cachedWeeks[currentWeekIndex]))
                        .font(AppTypography.h4)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .animation(.easeInOut(duration: AppAnimation.standard), value: isExpanded)

            Spacer()

            let currentTotal: Decimal? = isExpanded
                ? monthlyTotals[currentMonthIndex]
                : weeklyTotals[currentWeekIndex]
            if let total = currentTotal, total > 0 {
                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: total).doubleValue,
                    currency: baseCurrency,
                    fontSize: AppTypography.h4,
                    color: AppColors.textPrimary
                )
                .animation(.easeInOut(duration: AppAnimation.standard), value: isExpanded)
            }

            Image(systemName: "chevron.down")
                .font(AppTypography.bodySmall.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(AppAnimation.contentSpring, value: isExpanded)
        }
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { toggleExpanded() }
    }

    // MARK: - Weekday Headers (static, shared by both modes)

    private var weekdayHeaderRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(height: 20)
            }
        }
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        Group {
            if isExpanded {
                GeometryReader { geometry in
                    TabView(selection: $currentMonthIndex) {
                        ForEach(Array(cachedMonths.enumerated()), id: \.offset) { index, monthStart in
                            monthGrid(for: monthStart, availableHeight: geometry.size.height)
                                .tag(index)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: AppAnimation.slow), value: currentMonthIndex)
                }
                .frame(height: calculateCalendarHeight())
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                TabView(selection: $currentWeekIndex) {
                    ForEach(Array(cachedWeeks.enumerated()), id: \.offset) { index, weekStart in
                        weekRow(for: weekStart)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: compactHeight)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }

    // MARK: - Week Row (compact mode)

    private func weekRow(for weekStart: Date) -> some View {
        let weekDays = (0..<7).compactMap { i in
            calendar.date(byAdding: .day, value: i, to: weekStart)
        }
        return LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
            ForEach(weekDays, id: \.self) { date in
                dateCell(for: date)
            }
        }
        .padding(.top, AppSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Month Grid

    private func monthGrid(for monthStart: Date, availableHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
            let days = calendarDays(for: monthStart)
            ForEach(days) { day in
                if let date = day.date {
                    dateCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 80)
                }
            }
        }
        .padding(.top, AppSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Date Cell

    private func dateCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let occurrences = subscriptionsOnDate(date)

        return VStack(spacing: AppSpacing.xs) {
            Text("\(calendar.component(.day, from: date))")
                .font(isToday ? AppTypography.body.weight(.semibold) : AppTypography.body)
                .foregroundStyle(isToday ? AppColors.accent : AppColors.textPrimary)
                .frame(width: 48, height: 48)
                .background(isToday ? AppColors.accent.opacity(0.1) : Color.clear)
                .clipShape(Circle())
                .animation(.easeInOut(duration: AppAnimation.fast), value: isToday)

            if !occurrences.isEmpty {
                HStack(spacing: -AppSpacing.xs) {
                    ForEach(occurrences.prefix(3), id: \.id) { sub in
                        logoView(for: sub, size: AppIconSize.md)
                            .background(Circle().fill(AppColors.bgBase))
                            .clipShape(Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                    if occurrences.count > 3 {
                        Text("+\(occurrences.count - 3)")
                            .font(.system(size: AppIconSize.sm, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: AppIconSize.md, height: AppIconSize.md)
                            .background(Circle().fill(AppColors.bgCard))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(AppAnimation.contentSpring, value: occurrences.count)
            } else {
                Spacer().frame(height: AppIconSize.md)
            }
        }
        .frame(height: 80)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dateAccessibilityLabel(date: date, subscriptions: occurrences))
    }

    private func dateAccessibilityLabel(date: Date, subscriptions: [RecurringSeries]) -> String {
        let dateStr = date.formatted(date: .long, time: .omitted)
        if subscriptions.isEmpty {
            return dateStr
        }
        let names = subscriptions.map(\.description).joined(separator: ", ")
        return "\(dateStr), \(names)"
    }

    private func logoView(for sub: RecurringSeries, size: CGFloat) -> some View {
        IconView(source: sub.iconSource, size: size)
    }

    // MARK: - Toggle

    private func toggleExpanded() {
        if isExpanded {
            // Collapsing → week view. Keep the current week if it already belongs to the
            // displayed month; only re-anchor when the user swiped to a different month.
            guard cachedMonths.indices.contains(currentMonthIndex) else {
                withAnimation(AppAnimation.gentleSpring) { isExpanded.toggle() }
                return
            }
            currentWeekIndex = SubscriptionCalendarSync.collapsedWeekIndex(
                displayedMonth: cachedMonths[currentMonthIndex],
                currentWeekIndex: currentWeekIndex,
                weeks: cachedWeeks,
                today: Date(),
                calendar: calendar
            )
        } else {
            // Sync: find month matching the current week's start date
            let weekStart = cachedWeeks[currentWeekIndex]
            if let idx = cachedMonths.firstIndex(where: {
                calendar.isDate($0, equalTo: weekStart, toGranularity: .month)
            }) {
                currentMonthIndex = idx
            }
        }
        withAnimation(AppAnimation.gentleSpring) {
            isExpanded.toggle()
        }
    }

    // MARK: - Data Sources

    private func computeAllMonths() -> [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else {
            return [today]
        }
        return (0..<12).compactMap { i in
            calendar.date(byAdding: .month, value: i, to: startOfMonth)
        }
    }

    // 8 weeks before + current week + 47 weeks ahead = 56 weeks total
    // currentWeekIndex default = 8 (today's week)
    private func computeAllWeeks() -> [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let firstDayOffset = (weekday - calendar.firstWeekday + 7) % 7
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -firstDayOffset, to: today) else {
            return [today]
        }
        return (0..<56).compactMap { i in
            calendar.date(byAdding: .weekOfYear, value: i - 8, to: thisWeekStart)
        }
    }

    // MARK: - Height

    private var compactHeight: CGFloat {
        80 + AppSpacing.md
    }

    private func calculateCalendarHeight() -> CGFloat {
        let currentMonth = cachedMonths[currentMonthIndex]
        let days = calendarDays(for: currentMonth)
        let weeksCount = ceil(Double(days.count) / 7.0)

        let cellHeight: CGFloat = 80
        let rowSpacing: CGFloat = AppSpacing.xs * (weeksCount - 1)
        let gridHeight = (cellHeight * weeksCount) + rowSpacing
        let topPadding: CGFloat = AppSpacing.md

        return gridHeight + topPadding
    }

    // MARK: - Totals

    private func refreshTotals() async {
        await calculateAllMonthTotals()
        await calculateAllWeeklyTotals()
    }

    private func calculateAllMonthTotals() async {
        var totals: [Int: Decimal] = [:]
        let months = cachedMonths
        for (index, monthDate) in months.enumerated() {
            let monthStart = calendar.startOfDay(for: monthDate)
            guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
                continue
            }
            let monthInterval = DateInterval(start: monthStart, end: monthEnd)
            var monthTotal: Decimal = 0
            for subscription in subscriptions {
                let occurrences = subscription.occurrences(in: monthInterval)
                if !occurrences.isEmpty {
                    let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
                    let convertedAmount = await CurrencyConverter.convert(
                        amount: amount, from: subscription.currency, to: baseCurrency
                    ) ?? amount
                    monthTotal += Decimal(convertedAmount) * Decimal(occurrences.count)
                }
            }
            totals[index] = monthTotal
        }
        monthlyTotals = totals
    }

    private func calculateAllWeeklyTotals() async {
        var totals: [Int: Decimal] = [:]
        let weeks = cachedWeeks
        for (index, weekStart) in weeks.enumerated() {
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { continue }
            let weekInterval = DateInterval(start: weekStart, end: weekEnd.addingTimeInterval(-1))
            var weekTotal: Decimal = 0
            for subscription in subscriptions {
                let occurrences = subscription.occurrences(in: weekInterval)
                if !occurrences.isEmpty {
                    let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
                    let convertedAmount = await CurrencyConverter.convert(
                        amount: amount, from: subscription.currency, to: baseCurrency
                    ) ?? amount
                    weekTotal += Decimal(convertedAmount) * Decimal(occurrences.count)
                }
            }
            totals[index] = weekTotal
        }
        weeklyTotals = totals
    }

    // MARK: - Helpers

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstDay = calendar.firstWeekday
        var rotated = Array(symbols[firstDay-1..<symbols.count])
        rotated.append(contentsOf: symbols[0..<firstDay-1])
        return rotated
    }

    private func calendarDays(for monthStart: Date) -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart),
              let firstDayOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: monthStart)
              ) else {
            return []
        }

        let weekdayOfFirst = calendar.component(.weekday, from: firstDayOfMonth)
        let firstDayIndex = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [CalendarDay] = (0..<firstDayIndex).map { i in
            CalendarDay(id: "empty-\(i)", date: nil)
        }

        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                let comps = calendar.dateComponents([.year, .month, .day], from: date)
                guard let year = comps.year, let month = comps.month, let day = comps.day else { continue }
                let id = "\(year)-\(month)-\(day)"
                days.append(CalendarDay(id: id, date: date))
            }
        }
        return days
    }

    private func formatMonthYear(_ date: Date) -> String {
        Self.monthYearFormatter.string(from: date).capitalized
    }

    private func formatWeekRange(_ weekStart: Date) -> String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startStr = Self.shortDateFormatter.string(from: weekStart)
        let endStr = Self.shortDateFormatter.string(from: weekEnd)
        return "\(startStr) – \(endStr)"
    }

    private func subscriptionsOnDate(_ date: Date) -> [RecurringSeries] {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return [] }
        let key = "\(year)-\(month)-\(day)"
        return subscriptionsByDay[key] ?? []
    }

    /// Pre-compute which subscriptions fall on which day across the full calendar range.
    private func rebuildSubscriptionsByDay() {
        guard !cachedMonths.isEmpty, !cachedWeeks.isEmpty else { return }

        // Determine the full date range we need to cover
        let rangeStart = cachedWeeks.first ?? Date()
        guard let rangeEnd = calendar.date(byAdding: .month, value: 12, to: cachedMonths.first ?? Date()) else { return }
        let fullInterval = DateInterval(start: rangeStart, end: rangeEnd)

        var result: [String: [RecurringSeries]] = [:]
        for sub in subscriptions {
            let occurrences = sub.occurrences(in: fullInterval)
            for date in occurrences {
                let comps = calendar.dateComponents([.year, .month, .day], from: date)
                guard let year = comps.year, let month = comps.month, let day = comps.day else { continue }
                let key = "\(year)-\(month)-\(day)"
                result[key, default: []].append(sub)
            }
        }
        subscriptionsByDay = result
    }
}

// MARK: - Previews

#Preview("With Subscriptions") {
    let calendar = Calendar.current
    let today = Date()
    let formatter = ISO8601DateFormatter()

    let mockSubscriptions = [
        RecurringSeries(
            amount: 9.99,
            currency: "USD",
            category: "Развлечения",
            description: "Netflix",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: today))!),
            iconSource: .brandService("netflix")
        ),
        RecurringSeries(
            amount: 14.99,
            currency: "USD",
            category: "Развлечения",
            description: "Spotify",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 12, to: calendar.startOfDay(for: today))!),
            iconSource: .brandService("spotify")
        ),
        RecurringSeries(
            amount: 299,
            currency: "RUB",
            category: "Коммуналка",
            description: "Интернет",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!)
        ),
        RecurringSeries(
            amount: 4.99,
            currency: "USD",
            category: "Облако",
            description: "iCloud Storage",
            frequency: .monthly,
            startDate: formatter.string(from: today),
            iconSource: .brandService("icloud")
        )
    ]

    SubscriptionCalendarView(subscriptions: mockSubscriptions, baseCurrency: "USD")
        .padding()
}

#Preview("Empty Calendar") {
    SubscriptionCalendarView(subscriptions: [], baseCurrency: "USD")
        .padding()
}
