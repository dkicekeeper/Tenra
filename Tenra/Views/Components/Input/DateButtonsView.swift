//
//  DateButtonsView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

// MARK: - Main DateButtonsView
struct DateButtonsView: View {
    @Binding var selectedDate: Date
    var isDisabled: Bool = false
    let onSave: (Date) -> Void
    @State private var showingDatePicker = false

    var body: some View {
        DateButtonsContent(
            selectedDate: $selectedDate,
            isDisabled: isDisabled,
            onSave: onSave,
            showingDatePicker: $showingDatePicker
        )
    }
}

// MARK: - Shared Buttons Content
private struct DateButtonsContent: View {
    @Binding var selectedDate: Date
    var isDisabled: Bool = false
    let onSave: (Date) -> Void
    @Binding var showingDatePicker: Bool
    
    // Кешируем вычисление вчерашней даты
    private var yesterday: Date? {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())
    }
    
    private var today: Date {
        Date()
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Yesterday - left
            Button(action: {
                if let yesterday = yesterday {
                    selectedDate = yesterday
                    onSave(yesterday)
                }
            }) {
                Text(String(localized: "date.yesterday"))
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(isDisabled)

            // Today - center
            Button(action: {
                selectedDate = today
                onSave(today)
            }) {
                Text(String(localized: "date.today"))
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(isDisabled)

            // Calendar - right
            Button(action: {
                showingDatePicker = true
            }) {
                Text(String(localized: "date.selectDate"))
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(isDisabled)
        }
        .padding(AppSpacing.md)
        .sheet(isPresented: $showingDatePicker) {
            DateButtonsDatePickerSheet(
                selectedDate: $selectedDate,
                onDateSelected: { date in
                    onSave(date)
                    showingDatePicker = false
                }
            )
        }
    }
}

// MARK: - DatePicker Sheet Component
private struct DateButtonsDatePickerSheet: View {
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            DatePicker(
                String(localized: "date.choose"),
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle(String(localized: "date.choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.select")) {
                        onDateSelected(selectedDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - View Extension для использования через safeAreaInset
extension View {
    /// Добавляет DateButtonsView через safeAreaInset, чтобы компонент поднимался вместе с клавиатурой
    /// Используется в формах с текстовыми полями (AccountActionView, EditTransactionView, QuickAddTransactionView)
    func dateButtonsSafeArea(
        selectedDate: Binding<Date>,
        isDisabled: Bool = false,
        onSave: @escaping (Date) -> Void
    ) -> some View {
        self.safeAreaBar(edge: .bottom) {
            DateButtonsContentWrapper(
                selectedDate: selectedDate,
                isDisabled: isDisabled,
                onSave: onSave
            )
        }
    }
}

// MARK: - Wrapper для использования в safeAreaInset
private struct DateButtonsContentWrapper: View {
    @Binding var selectedDate: Date
    var isDisabled: Bool = false
    let onSave: (Date) -> Void
    @State private var showingDatePicker = false
    
    var body: some View {
        DateButtonsContent(
            selectedDate: $selectedDate,
            isDisabled: isDisabled,
            onSave: onSave,
            showingDatePicker: $showingDatePicker
        )
    }
}

#Preview {
    DateButtonsView(selectedDate: .constant(Date())) { _ in }
        .padding()
}
