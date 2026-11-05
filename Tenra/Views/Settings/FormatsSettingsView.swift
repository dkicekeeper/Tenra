//
//  FormatsSettingsView.swift
//  Tenra
//
//  Settings › Formats (docs/plan-formats.md §3.2): how the app writes dates and amounts. A live
//  preview on top (a day, three operations and the week), then the five choices. Each row shows
//  the current option by its short name and opens its options (FormatOptionsPage): a sample per
//  option with what it means under it, as in the approved mockup. Every choice starts at the
//  region's; "Use the region's format" returns all five there (FormatSettings). A change
//  rebuilds the tab roots (`FormatSettings.version`, TabViews), not their stacks, so this page
//  stays open.
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
                    choiceRow(
                        "formats.date", id: "formats.date", value: dateValue,
                        footer: "formats.date.footer", options: dateOptions, selection: dateBinding
                    )
                    choiceRow(
                        "formats.weekStart", id: "formats.weekStart", value: weekdayName(formats.resolved.firstWeekday),
                        footer: "formats.weekStart.footer", options: weekStartOptions, selection: weekStartBinding
                    )
                }

                FormSection(header: String(localized: "formats.section.amounts"), footer: footer) {
                    choiceRow(
                        "formats.separators", id: "formats.separators", value: separatorsValue,
                        footer: "formats.separators.footer", options: separatorOptions, selection: separatorsBinding
                    )
                    choiceRow(
                        "formats.symbol", id: "formats.symbol", value: symbolName(formats.resolved.symbol),
                        footer: "formats.symbol.footer", options: symbolOptions, selection: symbolBinding
                    )
                    choiceRow(
                        "formats.cents", id: "formats.cents", value: centsName(formats.resolved.cents),
                        footer: "formats.cents.footer", options: centsOptions, selection: centsBinding
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

    /// A choice: its title, the current option's short name, and its options on a page.
    private func choiceRow<Value: Hashable>(
        _ titleKey: String.LocalizationValue,
        id: String,
        value: String,
        footer footerKey: String.LocalizationValue,
        options: [FormatOption<Value>],
        selection: Binding<Value>
    ) -> some View {
        let title = String(localized: titleKey)
        return UniversalRow(
            title,
            value: value,
            accessory: .navigation {
                FormatOptionsPage(
                    title: title,
                    footer: String(localized: footerKey),
                    options: options,
                    selection: selection
                )
            }
        )
        .accessibilityIdentifier(id)
    }

    // MARK: - Preview

    /// A day, two expenses, an income and the week, as the app will write them. Rebuilt on
    /// every change: the rows' amounts read DesignKit's configuration, which SwiftUI does not
    /// observe.
    private var preview: some View {
        FormSection(header: String(localized: "formats.preview")) {
            VStack(alignment: .leading, spacing: 0) {
                Text(dateValue)
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

    /// DesignKit's badges: the first day filled, the others tinted.
    private func weekDays(_ days: [String]) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Badge(
                    day,
                    color: index == 0 ? AppColors.accent : AppColors.Text.secondary,
                    style: index == 0 ? .filled : .tinted
                )
            }
        }
    }

    // MARK: - Resolving

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

    // MARK: - Date

    /// Today in the current style, with its year (the row's value and the preview's day).
    private var dateValue: String {
        DateFormatters.day(Date(), includeYear: true, style: formats.resolved.dateStyle)
    }

    private var dateOptions: [FormatOption<DateStyle>] {
        let today = Date()
        return DateStyle.allCases.map { style in
            let hint: String = switch style {
            case .words: String(localized: wordsOrderKey)
            case .dots: String(localized: "formats.date.dots")
            case .slash: String(localized: "formats.date.slash")
            case .iso: String(localized: "formats.date.iso")
            }
            return FormatOption(title: DateFormatters.day(today, includeYear: true, style: style), hint: hint, value: style)
        }
    }

    /// The words style keeps the language's order ("3 ноября 2026", "November 3, 2026",
    /// "2026年11月3日"): its description says which.
    private var wordsOrderKey: String.LocalizationValue {
        let template = DateFormatter.dateFormat(fromTemplate: "dMMMMyyyy", options: 0, locale: .current) ?? "d MMMM yyyy"
        let pattern = template.replacingOccurrences(of: "'[^']*'", with: "", options: .regularExpression)
        let position = { (field: Character) in pattern.firstIndex(of: field) ?? pattern.endIndex }
        if position("y") < position("M") { return "formats.date.wordsYearFirst" }
        if position("M") < position("d") { return "formats.date.wordsMonthFirst" }
        return "formats.date.wordsDayFirst"
    }

    private var dateBinding: Binding<DateStyle> {
        Binding(
            get: { formats.resolved.dateStyle },
            set: { style in formats.set { $0.date = style } }
        )
    }

    // MARK: - First day of the week

    private func weekdayName(_ day: Int) -> String {
        let names = AppCalendar.current.standaloneWeekdaySymbols
        let name = names.indices.contains(day - 1) ? names[day - 1] : String(day)
        return name.capitalized(with: .current)
    }

    /// Monday, Sunday and the region's own day.
    private var weekStartOptions: [FormatOption<Int>] {
        var days = FormatPreferences.weekStartOptions(regionFirstWeekday: region.firstWeekday)
        // A day chosen in another region stays listed, so it still shows as chosen.
        if !days.contains(formats.resolved.firstWeekday) { days.append(formats.resolved.firstWeekday) }
        return days.map { FormatOption(title: weekdayName($0), hint: nil, value: $0) }
    }

    private var weekStartBinding: Binding<Int> {
        Binding(
            get: { formats.resolved.firstWeekday },
            set: { day in formats.set { $0.firstWeekday = day } }
        )
    }

    // MARK: - Separators

    private var separatorChoices: [AmountSeparators] {
        FormatPreferences.separatorOptions(region: region)
    }

    /// Thousands and cents in `option`'s marks.
    private func separatorSample(_ option: AmountSeparators) -> String {
        // The region's own grouping (India's 1,23,456.78) shows only past a hundred thousand.
        let sample = option == .region ? 123_456.78 : 1_234.56
        return amounts { $0.separators = option }.formattedNumber(sample, alwaysShowFraction: true) ?? ""
    }

    private var separatorsValue: String {
        separatorSample(selectedSeparators)
    }

    private var separatorOptions: [FormatOption<AmountSeparators>] {
        separatorChoices.map { option in
            let hint: String = switch option {
            case .spaceComma: String(localized: "formats.separators.spaceComma")
            case .commaDot: String(localized: "formats.separators.commaDot")
            case .dotComma: String(localized: "formats.separators.dotComma")
            case .apostropheDot: String(localized: "formats.separators.apostropheDot")
            case .spaceDot: String(localized: "formats.separators.spaceDot")
            case .region: String(localized: "formats.separators.region")
            }
            return FormatOption(title: separatorSample(option), hint: hint, value: option)
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

    // MARK: - Currency symbol

    private func symbolName(_ position: AmountSymbolPosition) -> String {
        switch position {
        case .after: String(localized: "formats.symbol.after")
        case .before: String(localized: "formats.symbol.before")
        }
    }

    /// The base currency's sample in each place, its name under it.
    private var symbolOptions: [FormatOption<AmountSymbolPosition>] {
        [AmountSymbolPosition.after, .before].map { position in
            let sample = Formatting.formatCurrencySmart(
                1_234, currency: currency, configuration: amounts { $0.symbol = position })
            return FormatOption(title: sample, hint: symbolName(position), value: position)
        }
    }

    private var symbolBinding: Binding<AmountSymbolPosition> {
        Binding(
            get: { formats.resolved.symbol },
            set: { position in formats.set { $0.symbol = position } }
        )
    }

    // MARK: - Cents

    private func centsName(_ cents: CentsDisplay) -> String {
        switch cents {
        case .whenPresent: String(localized: "formats.cents.whenPresent")
        case .always: String(localized: "formats.cents.always")
        case .never: String(localized: "formats.cents.never")
        }
    }

    /// Each mode's name, and under it what it does to a whole amount and to one with cents.
    private var centsOptions: [FormatOption<CentsDisplay>] {
        CentsDisplay.allCases.map { cents in
            let configuration = amounts { $0.cents = cents }
            let number = { (value: Double) in configuration.formattedNumber(value) ?? "" }
            let hint = switch cents {
            case .whenPresent:
                String(format: String(localized: "formats.cents.bothSamples"), number(1_234), number(1_234.5))
            case .always:
                number(1_234)
            case .never:
                String(format: String(localized: "formats.cents.rounded"), number(1_234.5))
            }
            return FormatOption(title: centsName(cents), hint: hint, value: cents)
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

// MARK: - Options page

/// One option of a choice: its sample (or name) and what it means.
struct FormatOption<Value: Hashable> {
    let title: String
    let hint: String?
    let value: Value
}

/// The options of one choice (the mockup's list): each its sample with what it means under it,
/// the chosen one marked, and the choice's footer. A tap chooses it and goes back to Formats.
private struct FormatOptionsPage<Value: Hashable>: View {
    let title: String
    let footer: String
    let options: [FormatOption<Value>]
    @Binding var selection: Value

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            FormSection(footer: footer) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    UniversalRow(
                        option.title,
                        hint: option.hint,
                        accessory: .checkmark(isSelected: option.value == selection) {
                            selection = option.value
                            dismiss()
                        }
                    )
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
