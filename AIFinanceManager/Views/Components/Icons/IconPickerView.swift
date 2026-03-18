//
//  IconPickerView.swift
//  AIFinanceManager
//
//  Unified icon/logo picker with segmented control for all entities
//

import SwiftUI

struct IconPickerView: View {
    @Binding var selectedSource: IconSource?
    var allowLogos: Bool = true
    @Environment(\.dismiss) private var dismiss

    @State private var pickerMode: PickerMode = .icons

    enum PickerMode: String, CaseIterable {
        case icons
        case logos

        var localizedTitle: String {
            switch self {
            case .icons: return String(localized: "iconPicker.iconsTab")
            case .logos: return String(localized: "iconPicker.logosTab")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // Content
                switch pickerMode {
                case .icons:
                    IconsTabView(selectedSource: $selectedSource)
                case .logos:
                    LogosTabView(selectedSource: $selectedSource)
                }
            }
            .safeAreaInset(edge: .top) {
                if allowLogos {
                    SegmentedPickerView(
                        title: "",
                        selection: $pickerMode,
                        options: PickerMode.allCases.map { (label: $0.localizedTitle, value: $0) }
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    .background(Color.clear)
                }
            }
            .navigationTitle(String(localized: "iconPicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .glassProminentButton()
                }
            }
        }
    }
}

// MARK: - Icons Tab

private struct IconsTabView: View {
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    private let iconCategories: [(String, [String])] = [
        (String(localized: "iconPicker.frequentlyUsed"), ["banknote.fill", "cart.fill", "car.fill", "bag.fill", "fork.knife", "house.fill", "briefcase.fill", "heart.fill", "airplane", "gift.fill", "creditcard.fill", "tv.fill", "book.fill", "star.fill", "bolt.fill", "flame.fill"]),
        (String(localized: "iconPicker.foodAndDrinks"), ["fork.knife", "cup.and.saucer.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill", "carrot.fill", "fish.fill", "leaf.fill", "mug.fill"]),
        (String(localized: "iconPicker.transport"), ["car.fill", "bus.fill", "airplane", "tram.fill", "bicycle", "scooter", "ferry.fill", "fuelpump.fill"]),
        (String(localized: "iconPicker.shopping"), ["bag.fill", "cart.fill", "creditcard.fill", "handbag.fill", "tshirt.fill", "giftcard.fill", "basket.fill", "tag.fill"]),
        (String(localized: "iconPicker.entertainment"), ["film.fill", "gamecontroller.fill", "music.note", "theatermasks.fill", "paintpalette.fill", "book.fill", "sportscourt.fill", "figure.walk"]),
        (String(localized: "iconPicker.health"), ["cross.case.fill", "heart.text.square.fill", "bandage.fill", "syringe.fill", "cross.fill", "eye.fill", "waveform.path.ecg", "figure.run"]),
        (String(localized: "iconPicker.homeAndUtilities"), ["house.fill", "key.fill", "chair.fill", "bed.double.fill", "lightbulb.fill", "sparkles", "sofa.fill", "shower.fill"]),
        (String(localized: "iconPicker.moneyAndFinance"), ["banknote.fill", "dollarsign.circle.fill", "creditcard.fill", "building.columns.fill", "chart.bar.fill", "rublesign.circle.fill", "eurosign.circle.fill"])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                ForEach(iconCategories, id: \.0) { category in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        SectionHeaderView(category.0, style: .compact)
                            .padding(.horizontal, AppSpacing.lg)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.lg), count: 5),
                            spacing: AppSpacing.lg
                        ) {
                            ForEach(category.1, id: \.self) { iconName in
                                IconButton(
                                    iconName: iconName,
                                    isSelected: selectedSource == .sfSymbol(iconName),
                                    onTap: {
                                        HapticManager.selection()
                                        selectedSource = .sfSymbol(iconName)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                }
            }
            .padding(.vertical, AppSpacing.lg)
        }
    }
}

// MARK: - Icon Button

private struct IconButton: View {
    let iconName: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            IconView(
                source: .sfSymbol(iconName),
                style: .circle(
                    size: AppIconSize.xxxl,
                    tint: .monochrome(isSelected ? .white : AppColors.textPrimary)
                )
            )
            .frame(width: AppIconSize.mega, height: AppIconSize.mega)
            .background(isSelected ? AppColors.accent : AppColors.surface)
            .clipShape(.rect(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logos Tab

private struct LogosTabView: View {
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [ServiceLogoEntry] {
        ServiceLogoRegistry.search(query: searchText)
    }

    var body: some View {
        Group {
            if isSearching {
                SearchResultsView(
                    searchText: searchText,
                    results: Array(searchResults.prefix(8)),
                    selectedSource: $selectedSource
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                        ForEach(ServiceCategory.allCases, id: \.rawValue) { category in
                            let entries = ServiceLogoRegistry.services(for: category)
                            if !entries.isEmpty {
                                LogoCategorySection(
                                    title: category.localizedTitle,
                                    items: entries.map { .service($0) },
                                    selectedSource: $selectedSource
                                )
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.lg)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: String(localized: "iconPicker.searchOnline")
        )
    }
}

// MARK: - Logo Category Section

private struct LogoCategorySection: View {
    let title: String
    let items: [LogoItem]
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SectionHeaderView(title, style: .compact)
                .padding(.horizontal, AppSpacing.lg)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.lg), count: 5),
                spacing: AppSpacing.lg
            ) {
                ForEach(items) { item in
                    LogoItemButton(
                        item: item,
                        isSelected: item.iconSource == selectedSource,
                        onTap: {
                            HapticManager.selection()
                            selectedSource = item.iconSource
                            dismiss()
                        }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

// MARK: - Logo Item

private enum LogoItem: Identifiable {
    case bank(BankLogo)
    case service(ServiceLogoEntry)

    var id: String {
        switch self {
        case .bank(let logo):
            return "bank_\(logo.rawValue)"
        case .service(let entry):
            return "service_\(entry.domain)"
        }
    }

    var iconSource: IconSource {
        switch self {
        case .bank(let logo):
            return .bankLogo(logo)
        case .service(let entry):
            return entry.iconSource
        }
    }
}

// MARK: - Logo Item Button

private struct LogoItemButton: View {
    let item: LogoItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            IconView(
                source: item.iconSource,
                size: AppIconSize.xxxl
            )
            .frame(width: AppIconSize.mega, height: AppIconSize.mega)
            .background(isSelected ? AppColors.accent.opacity(0.1) : AppColors.surface)
            .clipShape(.rect(cornerRadius: AppRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Results View

/// Two-phase search: local suggestions + online domain fallback
private struct SearchResultsView: View {
    let searchText: String
    let results: [ServiceLogoEntry]
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var looksLikeDomain: Bool {
        trimmedSearch.contains(".")
    }

    var body: some View {
        List {
            if !results.isEmpty {
                Section {
                    ForEach(results) { entry in
                        OnlineLogoRow(
                            iconSource: entry.iconSource,
                            displayLabel: entry.displayName,
                            isSelected: selectedSource == entry.iconSource,
                            onSelect: {
                                HapticManager.selection()
                                selectedSource = entry.iconSource
                                dismiss()
                            }
                        )
                    }
                } header: {
                    Text(String(localized: "iconPicker.suggestions"))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            Section {
                if looksLikeDomain {
                    OnlineLogoRow(
                        iconSource: .brandService(trimmedSearch),
                        displayLabel: trimmedSearch,
                        isSelected: selectedSource == .brandService(trimmedSearch),
                        onSelect: {
                            HapticManager.selection()
                            selectedSource = .brandService(trimmedSearch)
                            dismiss()
                        }
                    )
                } else {
                    OnlineLogoRow(
                        iconSource: .brandService("\(trimmedSearch).com"),
                        displayLabel: "\(trimmedSearch).com",
                        isSelected: selectedSource == .brandService("\(trimmedSearch).com"),
                        onSelect: {
                            HapticManager.selection()
                            selectedSource = .brandService("\(trimmedSearch).com")
                            dismiss()
                        }
                    )
                    OnlineLogoRow(
                        iconSource: .brandService("\(trimmedSearch).kz"),
                        displayLabel: "\(trimmedSearch).kz",
                        isSelected: selectedSource == .brandService("\(trimmedSearch).kz"),
                        onSelect: {
                            HapticManager.selection()
                            selectedSource = .brandService("\(trimmedSearch).kz")
                            dismiss()
                        }
                    )
                }
            } header: {
                Text(String(localized: "iconPicker.onlineSearch"))
                    .foregroundStyle(AppColors.textPrimary)
            } footer: {
                Text(String(localized: "iconPicker.brandDomainHint"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

// MARK: - Online Logo Row

private struct OnlineLogoRow: View {
    let iconSource: IconSource
    let displayLabel: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.md) {
                IconView(
                    source: iconSource,
                    size: AppIconSize.xxl
                )

                Text(displayLabel)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Icons Tab") {
    @Previewable @State var source: IconSource? = .sfSymbol("star.fill")
    return IconPickerView(selectedSource: $source)
}

#Preview("Logos Tab") {
    @Previewable @State var source: IconSource? = .bankLogo(.kaspi)
    return IconPickerView(selectedSource: $source)
}
