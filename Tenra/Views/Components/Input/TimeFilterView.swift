//
//  TimeFilterView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct TimeFilterView: View {
    @Bindable var filterManager: TimeFilterManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedPreset: TimeFilterPreset
    @State private var customDateRange: ClosedRange<Date>
    @State private var showingCustomPicker = false

    private let presetOptions = TimeFilterPreset.allCases.filter { $0 != .custom }

    init(filterManager: TimeFilterManager) {
        self.filterManager = filterManager
        let currentFilter = filterManager.currentFilter
        _selectedPreset = State(initialValue: currentFilter.preset)
        if currentFilter.preset == .custom {
            // endDate is exclusive (the day after the last picked one); show the picked days.
            let lastDay = max(currentFilter.startDate, currentFilter.lastIncludedDay)
            _customDateRange = State(initialValue: currentFilter.startDate...lastDay)
        } else {
            // Non-custom presets (e.g. .allTime) carry sentinel dates like 1970/2125 that
            // would render as the picker default — anchor on today instead.
            let today = Calendar.current.startOfDay(for: Date())
            _customDateRange = State(initialValue: today...today)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Presets
                Section {
                    ForEach(presetOptions, id: \.self) { preset in
                        UniversalRow(config: .settings) {
                            Text(preset.localizedName)
                                .font(AppTypography.h4)
                                .fontWeight(.regular)
                        } trailing: {
                            if selectedPreset == preset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                        .selectableRow(isSelected: selectedPreset == preset) {
                            selectedPreset = preset
                            filterManager.setPreset(preset)
                            dismiss()
                        }
                    }
                } header: {
                    SectionHeader(String(localized: "timeFilter.presets", defaultValue: "Пресеты"))
                }

                // MARK: - Custom Range
                Section {
                    UniversalRow(config: .settings) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(String(localized: "timeFilter.customPeriod", defaultValue: "Пользовательский период"))
                                .font(AppTypography.h4)
                                .fontWeight(.regular)
                            if selectedPreset == .custom {
                                Text(customRangeDescription)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    } trailing: {
                        if selectedPreset == .custom {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .selectableRow(isSelected: selectedPreset == .custom) {
                        selectedPreset = .custom
                        showingCustomPicker = true
                    }
                } header: {
                    SectionHeader(String(localized: "timeFilter.customRange", defaultValue: "Свой период"))
                }
            }
            .navigationTitle(String(localized: "timeFilter.title", defaultValue: "Фильтр по времени"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showingCustomPicker) {
                // DesignKit's DateRangePickerSheet (2.9.0): two calendars, the start never past the end.
                DateRangePickerSheet(range: customDateRange) { range in
                    filterManager.setCustomRange(from: range.lowerBound, through: range.upperBound)
                    showingCustomPicker = false
                    dismiss()
                }
            }
        }
    }

    /// Static formatter — allocated once, reused every body evaluation.
    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var customRangeDescription: String {
        "\(Self.rangeFormatter.string(from: customDateRange.lowerBound)) – \(Self.rangeFormatter.string(from: customDateRange.upperBound))"
    }
}

// MARK: - Previews

#Preview("Default") {
    TimeFilterView(filterManager: TimeFilterManager())
}

#Preview("Custom Range") {
    let manager = TimeFilterManager()
    manager.setCustomRange(
        from: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
        through: Date()
    )
    return TimeFilterView(filterManager: manager)
}
