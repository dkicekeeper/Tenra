//
//  MenuPickerRow.swift
//  AIFinanceManager
//
//  Reusable menu picker row with icon, title, and compact menu selection
//  Universal component for all single-select scenarios
//

import SwiftUI

/// Universal menu picker row for forms
/// Shows icon + title on left, selected value + menu on right
struct MenuPickerRow<T: Hashable>: View {
    let icon: String?
    let title: String
    @Binding var selection: T
    let options: [(label: String, value: T)]

    init(
        icon: String? = nil,
        title: String,
        selection: Binding<T>,
        options: [(label: String, value: T)]
    ) {
        self.icon = icon
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        UniversalRow(
            config: .standard,
            leadingIcon: icon.map { .sfSymbol($0, color: AppColors.accent, size: AppIconSize.lg) }
        ) {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
        } trailing: {
            Menu {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection = option.value
                    } label: {
                        HStack {
                            Text(option.label)
                            if selection == option.value {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                if let selectedOption = options.first(where: { $0.value == selection }) {
                    Text(selectedOption.label)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Convenience Initializers

extension MenuPickerRow where T == RecurringFrequency {
    /// Convenience initializer for RecurringFrequency (subscription frequency)
    init(
        icon: String? = "arrow.triangle.2.circlepath",
        title: String = String(localized: "common.frequency"),
        selection: Binding<RecurringFrequency>
    ) {
        self.icon = icon
        self.title = title
        self._selection = selection
        self.options = RecurringFrequency.allCases.map {
            (label: $0.displayName, value: $0)
        }
    }
}

extension MenuPickerRow where T == RecurringOption {
    /// Convenience initializer for RecurringOption (transaction recurring: never/daily/weekly/etc)
    init(
        icon: String? = "repeat",
        title: String = String(localized: "transactionForm.makeRecurring"),
        selection: Binding<RecurringOption>
    ) {
        self.icon = icon
        self.title = title
        self._selection = selection
        // Включаем "Никогда" + все частоты
        self.options = [
            (label: String(localized: "recurring.never"), value: .never)
        ] + RecurringFrequency.allCases.map {
            (label: $0.displayName, value: .frequency($0))
        }
    }
}

extension MenuPickerRow where T == ReminderOption {
    /// Convenience initializer for ReminderOption (subscription reminders)
    init(
        icon: String? = "bell",
        title: String = String(localized: "subscription.reminders"),
        selection: Binding<ReminderOption>
    ) {
        self.icon = icon
        self.title = title
        self._selection = selection
        // "Никогда" + стандартные напоминания
        self.options = [
            (label: String(localized: "reminder.none"), value: .none),
            (label: String(localized: "reminder.dayBefore.one"), value: .daysBefore(1)),
            (label: String(localized: "reminder.daysBefore.3"), value: .daysBefore(3)),
            (label: String(localized: "reminder.daysBefore.7"), value: .daysBefore(7)),
            (label: String(localized: "reminder.daysBefore.30"), value: .daysBefore(30))
        ]
    }
}

// MARK: - RecurringOption Enum

/// Option for recurring transactions: never or specific frequency
enum RecurringOption: Hashable {
    case never
    case frequency(RecurringFrequency)

    var displayName: String {
        switch self {
        case .never:
            return String(localized: "recurring.never")
        case .frequency(let freq):
            return freq.displayName
        }
    }
}

// MARK: - Previews

#Preview("Subscription Frequency") {
    @Previewable @State var frequency: RecurringFrequency = .monthly

    FormSection(
        header: String(localized: "subscription.basicInfo"),
        style: .card
    ) {
        MenuPickerRow(
            icon: "arrow.triangle.2.circlepath",
            title: String(localized: "common.frequency"),
            selection: $frequency
        )
    }
    .padding()
}

#Preview("Transaction Recurring") {
    @Previewable @State var recurring: RecurringOption = .never

    FormSection(
        header: "Recurring Settings",
        style: .card
    ) {
        MenuPickerRow(
            icon: "repeat",
            title: String(localized: "transactionForm.makeRecurring"),
            selection: $recurring
        )
    }
    .padding()
}

#Preview("Generic String Options") {
    @Previewable @State var priority = "Medium"

    FormSection(
        header: "Task Settings",
        style: .card
    ) {
        MenuPickerRow(
            icon: "flag.fill",
            title: "Priority",
            selection: $priority,
            options: [
                (label: "Low", value: "Low"),
                (label: "Medium", value: "Medium"),
                (label: "High", value: "High")
            ]
        )
    }
    .padding()
}

#Preview("Without Icon") {
    @Previewable @State var category = "Work"

    FormSection(style: .card) {
        MenuPickerRow(
            title: "Category",
            selection: $category,
            options: [
                (label: "Work", value: "Work"),
                (label: "Personal", value: "Personal"),
                (label: "Family", value: "Family")
            ]
        )
    }
    .padding()
}

#Preview("Complete Form Example") {
    @Previewable @State var name = ""
    @Previewable @State var frequency: RecurringFrequency = .monthly
    @Previewable @State var recurring: RecurringOption = .never
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

                MenuPickerRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: String(localized: "common.frequency"),
                    selection: $frequency
                )
                Divider()

                DatePickerRow(
                    title: String(localized: "common.startDate"),
                    selection: $startDate
                )
            }

            FormSection(
                header: "Transaction Settings",
                style: .card
            ) {
                MenuPickerRow(
                    icon: "repeat",
                    title: "Recurring",
                    selection: $recurring
                )
            }
        }
        .padding()
    }
}

#Preview("All Frequencies Visible") {
    @Previewable @State var frequency: RecurringFrequency = .monthly

    VStack(spacing: AppSpacing.lg) {
        Text("Selected: \(frequency.displayName)")
            .font(AppTypography.h4)
            .padding()

        FormSection(style: .card) {
            MenuPickerRow(
                title: String(localized: "common.frequency"),
                selection: $frequency
            )
        }

        // Show what menu looks like
        Text("Tap the menu to see all options →")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
    }
    .padding()
}
