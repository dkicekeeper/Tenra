//
//  SubscriptionCalendarView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

private struct CalendarDay: Identifiable {
    let id: String
    let date: Date?
}

struct SubscriptionCalendarView: View {
    let subscriptions: [RecurringSeries]
    let baseCurrency: String

    @State private var isExpanded = false
    @State private var currentMonthIndex: Int = 0
    @State private var currentWeekIndex: Int = 8 // weeksBefore = 8, index 8 = current week
    @State private var monthlyTotals: [Int: Decimal] = [:]
    @State private var weeklyTotals: [Int: Decimal] = [:]

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
        .task {
            await refreshTotals()
        }
        .onChange(of: subscriptions.count) { _, _ in
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
                        Text(formatMonthYear(allMonths[currentMonthIndex]))
                            .font(AppTypography.h4)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(formatWeekRange(allWeeks[currentWeekIndex]))
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

            Button(action: toggleExpanded) {
                Image(systemName: "chevron.down")
                    .font(AppTypography.bodySmall.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(AppAnimation.contentSpring, value: isExpanded)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppSpacing.sm)
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
                        ForEach(Array(allMonths.enumerated()), id: \.offset) { index, monthStart in
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
                    ForEach(Array(allWeeks.enumerated()), id: \.offset) { index, weekStart in
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
                        .frame(height: 60)
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
                            .background(Circle().fill(AppColors.backgroundPrimary))
                            .clipShape(Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                    if occurrences.count > 3 {
                        Text("+\(occurrences.count - 3)")
                            .font(.system(size: AppIconSize.sm, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: AppIconSize.md, height: AppIconSize.md)
                            .background(Circle().fill(AppColors.surface))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(AppAnimation.contentSpring, value: occurrences.count)
            } else {
                Spacer().frame(height: AppIconSize.md)
            }
        }
        .frame(height: 64)
    }

    private func logoView(for sub: RecurringSeries, size: CGFloat) -> some View {
        IconView(source: sub.iconSource, size: size)
    }

    // MARK: - Toggle

    private func toggleExpanded() {
        if isExpanded {
            // Sync: find week containing the first day of the current month
            let monthStart = allMonths[currentMonthIndex]
            let weeks = allWeeks
            if let idx = weeks.firstIndex(where: { weekStart in
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return false }
                return weekStart <= monthStart && monthStart < weekEnd
            }) {
                currentWeekIndex = idx
            }
        } else {
            // Sync: find month matching the current week's start date
            let weekStart = allWeeks[currentWeekIndex]
            if let idx = allMonths.firstIndex(where: {
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

    private var allMonths: [Date] {
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
    private var allWeeks: [Date] {
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
        60 + AppSpacing.md
    }

    private func calculateCalendarHeight() -> CGFloat {
        let currentMonth = allMonths[currentMonthIndex]
        let days = calendarDays(for: currentMonth)
        let weeksCount = ceil(Double(days.count) / 7.0)

        let cellHeight: CGFloat = 60
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
        for (index, monthDate) in allMonths.enumerated() {
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
        for (index, weekStart) in allWeeks.enumerated() {
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
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: date) else { return [] }
        let dayInterval = DateInterval(start: date, end: endDate.addingTimeInterval(-1))
        return subscriptions.filter { sub in
            !sub.occurrences(in: dayInterval).isEmpty
        }
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
