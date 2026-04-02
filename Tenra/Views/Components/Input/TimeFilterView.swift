//
//  TimeFilterView.swift
//  AIFinanceManager
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
        _selectedPreset = State(initialValue: filterManager.currentFilter.preset)
        let start = filterManager.currentFilter.startDate
        let end = filterManager.currentFilter.endDate
        _customDateRange = State(initialValue: start...end)
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
                    SectionHeaderView(String(localized: "timeFilter.presets", defaultValue: "Пресеты"))
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
                    SectionHeaderView(String(localized: "timeFilter.customRange", defaultValue: "Свой период"))
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
                CustomPeriodPickerSheet(dateRange: $customDateRange) { range in
                    filterManager.setCustomRange(start: range.lowerBound, end: range.upperBound)
                    showingCustomPicker = false
                    dismiss()
                }
            }
        }
    }

    private var customRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: customDateRange.lowerBound)) – \(formatter.string(from: customDateRange.upperBound))"
    }
}

// MARK: - Custom Period Picker Sheet

private struct CustomPeriodPickerSheet: View {
    @Binding var dateRange: ClosedRange<Date>
    let onApply: (ClosedRange<Date>) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var localRange: ClosedRange<Date>

    init(dateRange: Binding<ClosedRange<Date>>, onApply: @escaping (ClosedRange<Date>) -> Void) {
        self._dateRange = dateRange
        self.onApply = onApply
        _localRange = State(initialValue: dateRange.wrappedValue)
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { localRange.lowerBound },
            set: { newStart in
                let end = max(newStart, localRange.upperBound)
                localRange = newStart...end
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { localRange.upperBound },
            set: { newEnd in
                let start = min(localRange.lowerBound, newEnd)
                localRange = start...newEnd
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    DatePicker(
                        String(localized: "timeFilter.from", defaultValue: "С"),
                        selection: startBinding,
                        in: ...localRange.upperBound,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, AppSpacing.md)

                    Divider()

                    DatePicker(
                        String(localized: "timeFilter.to", defaultValue: "По"),
                        selection: endBinding,
                        in: localRange.lowerBound...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, AppSpacing.md)
                }
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle(String(localized: "timeFilter.customPeriod", defaultValue: "Пользовательский период"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "button.apply", defaultValue: "Применить")) {
                        onApply(localRange)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Previews

#Preview("Default") {
    TimeFilterView(filterManager: TimeFilterManager())
}

#Preview("Custom Range") {
    let manager = TimeFilterManager()
    manager.setCustomRange(
        start: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
        end: Date()
    )
    return TimeFilterView(filterManager: manager)
}
