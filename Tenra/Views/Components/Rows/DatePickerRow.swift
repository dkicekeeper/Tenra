//
//  DatePickerRow.swift
//  AIFinanceManager
//
//  Simplified date picker row - inline style only
//  For button-based selection, use DateButtonsView directly
//

import SwiftUI

/// Date picker row with inline style
/// For button-based selection (Yesterday/Today/Calendar), use DateButtonsView directly
struct DatePickerRow: View {
    let icon: String?
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents

    init(
        icon: String? = nil,
        title: String = String(localized: "common.startDate"),
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .date
    ) {
        self.icon = icon
        self.title = title
        self._selection = selection
        self.displayedComponents = displayedComponents
    }

    var body: some View {
        UniversalRow(
            config: .standard,
            leadingIcon: icon.map { .sfSymbol($0, color: AppColors.textPrimary, size: AppIconSize.lg) }
        ) {
            DatePicker(
                title,
                selection: $selection,
                displayedComponents: displayedComponents
            )
        } trailing: {
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("With Icon") {
    @Previewable @State var date = Date()

    FormSection(
        header: "Subscription Details",
        style: .card
    ) {
        TextField("Name", text: .constant("Netflix"))
            .padding(AppSpacing.lg)

        Divider()
            .padding(.leading, AppSpacing.lg)

        DatePickerRow(
            icon: "calendar",
            title: String(localized: "common.startDate"),
            selection: $date
        )
    }
    .padding()
}

#Preview("Without Icon") {
    @Previewable @State var date = Date()

    FormSection(
        header: "Subscription Details",
        style: .card
    ) {
        DatePickerRow(
            title: String(localized: "common.startDate"),
            selection: $date
        )
    }
    .padding()
}

#Preview("Date & Time with Icon") {
    @Previewable @State var datetime = Date()

    FormSection(
        header: "Appointment",
        style: .card
    ) {
        DatePickerRow(
            icon: "clock",
            title: "Date & Time",
            selection: $datetime,
            displayedComponents: [.date, .hourAndMinute]
        )
    }
    .padding()
}

#Preview("In Form Context") {
    @Previewable @State var name = ""
    @Previewable @State var amount = ""
    @Previewable @State var startDate = Date()

    ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            FormSection(
                header: String(localized: "subscription.basicInfo"),
                style: .card
            ) {
                FormTextField(
                    text: $name,
                    placeholder: String(localized: "subscription.namePlaceholder")
                )
                Divider()
                FormTextField(
                    text: $amount,
                    placeholder: "0.00",
                    keyboardType: .decimalPad
                )
                Divider()
                DatePickerRow(
                    title: String(localized: "common.startDate"),
                    selection: $startDate
                )
            }
        }
        .padding()
    }
}
