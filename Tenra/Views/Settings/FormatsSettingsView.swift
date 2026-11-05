//
//  FormatsSettingsView.swift
//  Tenra
//
//  Settings › Formats (docs/plan-formats.md §3.2): how the app writes dates and amounts. A live
//  preview on top (a day, three operations and the week), then the five choices, each a
//  DesignKit picker row whose options are samples. Every choice starts at the region's;
//  "Use the region's format" returns all five there (FormatSettings). A change rebuilds the
//  tab roots (`FormatSettings.version`, TabViews), not their stacks, so this page stays open.
//

import SwiftUI

struct FormatsSettingsView: View {
    /// The base currency: the preview's amounts and the currency symbol's samples.
    let currency: String

    @Environment(FormatSettings.self) private var formats

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                preview

                FormSection(header: String(localized: "formats.section.dates")) {
                    UniversalRow(
                        String(localized: "formats.date"),
                        accessory: .picker(dateBinding, options: dateOptions)
                    )
                    UniversalRow(
                        String(localized: "formats.weekStart"),
                        accessory: .picker(weekStartBinding, options: weekStartOptions)
                    )
                }

                FormSection(header: String(localized: "formats.section.amounts"), footer: footer) {
                    UniversalRow(
                        String(localized: "formats.separators"),
                        accessory: .picker(separatorsBinding, options: separatorOptions)
                    )
                    UniversalRow(
                        String(localized: "formats.symbol"),
                        accessory: .picker(symbolBinding, options: symbolOptions)
                    )
                    UniversalRow(
                        String(localized: "formats.cents"),
                        accessory: .picker(centsBinding, options: centsOptions)
                    )
                }

                // Only while a choice differs from the region's (§3.1).
                if formats.isCustomized {
                    DSButton(
                        String(localized: "formats.reset"),
                        appearance: .secondary,
                        fullWidth: true
                    ) {
                        formats.resetToRegion()
                    }
                    .transition(.opacity)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
            .animation(AppAnimation.contentSpring, value: formats.isCustomized)
        }
        .navigationTitle(String(localized: "settings.formats"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preview

    /// A day, two expenses, an income and the week, as the app will write them. Rebuilt on
    /// every change: the rows' amounts read DesignKit's configuration, which SwiftUI does not
    /// observe.
    private var preview: some View {
        FormSection(header: String(localized: "formats.preview")) {
            VStack(alignment: .leading, spacing: 0) {
                Text(DateFormatters.day(Date(), includeYear: true, style: formats.resolved.dateStyle))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
                previewRow("groceries", type: .expense, amount: 12_345.5)
            }
            .padding(.top, AppSpacing.md)
            .rowDividerInset(AppIconSize.Tile.sm + AppSpacing.md)
            previewRow("dining", type: .expense, amount: 1_800)
            previewRow("salary", type: .income, amount: 450_000)
            weekStrip
        }
        // Sample amounts, not the person's: shown even while Home's eye hides amounts.
        .amountsHidden(false)
        .id(formats.version)
    }

    /// An operation in one of the onboarding's categories.
    private func previewRow(_ presetId: String, type: TransactionType, amount: Double) -> some View {
        let preset = (CategoryPreset.defaultExpense + CategoryPreset.defaultIncome).first { $0.id == presetId }
        let title = preset.map { String(localized: String.LocalizationValue($0.nameKey)) } ?? ""
        let color = preset.map { Color(hex: $0.colorHex) } ?? AppColors.accent
        let prefix = TransactionDisplayHelper.amountPrefix(for: type)
        return TransactionRow(
            .entry(title: title),
            icon: preset?.iconSource,
            iconTint: .monochrome(color),
            iconBackground: AppColors.pale(color),
            amounts: [TransactionRow.Amount(
                amount,
                currency: currency,
                prefix: prefix,
                color: TransactionDisplayHelper.amountColor(for: type)
            )],
            accessibilityLabel: "\(title), \(prefix)\(Formatting.formatCurrencySmart(amount, currency: currency))"
        )
    }

    /// The week from its first day, that day marked; under its label when the line is too narrow.
    private var weekStrip: some View {
        let symbols = AppCalendar.current.shortWeekdaySymbols
        let first = formats.resolved.firstWeekday
        let days = symbols.indices.map { symbols[(first - 1 + $0) % symbols.count].capitalized(with: .current) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.sm) {
                weekLabel
                Spacer(minLength: 0)
                weekDays(days)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                weekLabel
                weekDays(days)
            }
        }
        // The section centres a row narrower than the card.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private var weekLabel: some View {
        Text(String(localized: "formats.preview.week"))
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.Text.secondary)
    }

    private func weekDays(_ days: [String]) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                if index == 0 {
                    Badge(day, style: .filled)
                } else {
                    // A badge's text and height, without its capsule.
                    Text(verbatim: day)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.primary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.xxs)
                        .fixedSize()
                }
            }
        }
    }

    // MARK: - Choices

    private var region: ResolvedFormats {
        FormatPreferences.region(for: formats.regionLocale)
    }

    /// What `edit` would look like, the other choices as they are now.
    private func resolving(_ edit: (inout FormatChoices) -> Void) -> ResolvedFormats {
        var choices = formats.choices
        edit(&choices)
        return FormatPreferences.resolve(choices, locale: formats.regionLocale)
    }

    /// DesignKit's amounts as `edit` would make them.
    private func amounts(_ edit: (inout FormatChoices) -> Void) -> AmountDisplayConfiguration {
        DesignKitBridge.amountConfiguration(resolving(edit))
    }

    /// "If any (1 234 and 1 234,50)": the option's name and what it does.
    private func named(_ nameKey: String.LocalizationValue, _ samples: [String]) -> String {
        "\(String(localized: nameKey)) (\(samples.formatted(.list(type: .and))))"
    }

    // Date: today in each style, as a date of this year reads (ISO always has its year; the
    // preview above shows the year). With the year "5 November 2026" did not fit the row's value.

    private var dateOptions: [(label: String, value: DateStyle)] {
        let today = Date()
        return DateStyle.allCases.map { (DateFormatters.day(today, includeYear: false, style: $0), $0) }
    }

    private var dateBinding: Binding<DateStyle> {
        Binding(
            get: { formats.resolved.dateStyle },
            set: { style in formats.set { $0.date = style } }
        )
    }

    // First day of the week: Monday, Sunday and the region's own day.

    private var weekStartOptions: [(label: String, value: Int)] {
        var days = FormatPreferences.weekStartOptions(regionFirstWeekday: region.firstWeekday)
        // A day chosen in another region stays listed, so the row still shows it.
        if !days.contains(formats.resolved.firstWeekday) { days.append(formats.resolved.firstWeekday) }
        let names = AppCalendar.current.standaloneWeekdaySymbols
        return days.map { day in
            let name = names.indices.contains(day - 1) ? names[day - 1] : String(day)
            return (name.capitalized(with: .current), day)
        }
    }

    private var weekStartBinding: Binding<Int> {
        Binding(
            get: { formats.resolved.firstWeekday },
            set: { day in formats.set { $0.firstWeekday = day } }
        )
    }

    // Separators: thousands and cents in each.

    private var separatorChoices: [AmountSeparators] {
        FormatPreferences.separatorOptions(region: region)
    }

    private var separatorOptions: [(label: String, value: AmountSeparators)] {
        separatorChoices.map { option in
            let configuration = amounts { $0.separators = option }
            // The region's own grouping (India's 1,23,456.78) shows only past a hundred thousand.
            let sample = option == .region ? 123_456.78 : 1_234.56
            return (configuration.formattedNumber(sample, alwaysShowFraction: true) ?? "", option)
        }
    }

    private var separatorsBinding: Binding<AmountSeparators> {
        Binding(
            get: { selectedSeparators },
            set: { option in formats.set { $0.separators = option } }
        )
    }

    /// The chosen option, or the one that looks like the region's (the region's own when none
    /// of the five does).
    private var selectedSeparators: AmountSeparators {
        let options = separatorChoices
        if let chosen = formats.choices.separators, options.contains(chosen) { return chosen }
        return options.first { option in
            option != .region
                && FormatPreferences.isEquivalent(resolving { $0.separators = option }, formats.resolved)
        } ?? .region
    }

    // Currency symbol: after or before, with the base currency.

    private var symbolOptions: [(label: String, value: AmountSymbolPosition)] {
        [(AmountSymbolPosition.after, "formats.symbol.after"), (.before, "formats.symbol.before")]
            .map { position, nameKey in
                let sample = Formatting.formatCurrencySmart(
                    1_234, currency: currency, configuration: amounts { $0.symbol = position })
                return (named(String.LocalizationValue(nameKey), [sample]), position)
            }
    }

    private var symbolBinding: Binding<AmountSymbolPosition> {
        Binding(
            get: { formats.resolved.symbol },
            set: { position in formats.set { $0.symbol = position } }
        )
    }

    // Cents: what each does to a whole amount and to one with cents.

    private var centsOptions: [(label: String, value: CentsDisplay)] {
        CentsDisplay.allCases.map { cents in
            let configuration = amounts { $0.cents = cents }
            let number = { (value: Double) in configuration.formattedNumber(value) ?? "" }
            switch cents {
            case .whenPresent: return (named("formats.cents.whenPresent", [number(1_234), number(1_234.5)]), cents)
            case .always: return (named("formats.cents.always", [number(1_234)]), cents)
            case .never: return (named("formats.cents.never", [number(1_234.5)]), cents)
            }
        }
    }

    private var centsBinding: Binding<CentsDisplay> {
        Binding(
            get: { formats.resolved.cents },
            set: { cents in formats.set { $0.cents = cents } }
        )
    }

    // MARK: - Footer

    /// The region the defaults come from, by name, and what the formats leave alone.
    private var footer: String {
        let code = formats.regionLocale.region?.identifier
        let name = code.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? code ?? ""
        return String(format: String(localized: "formats.footer"), name)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FormatsSettingsView(currency: "KZT")
    }
    // Required: the view reads `@Environment(FormatSettings.self)`.
    .environment(FormatSettings(defaults: UserDefaults(suiteName: "preview.formats") ?? .standard))
}
