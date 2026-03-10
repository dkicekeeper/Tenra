//
//  FormLabeledRow.swift
//  AIFinanceManager
//
//  Label-value row primitive for form groups.
//  The label stays visible at all times (unlike placeholder-only inputs),
//  matching the Revolut / N26 "labeled row" pattern.
//
//  Use inside `FormSection(style: .card)` separated by `Divider()`.
//
//  Usage:
//  ```swift
//  // Text input
//  FormLabeledRow(icon: "building.columns", label: "Bank") {
//      TextField("Enter bank name", text: $bankName)
//          .multilineTextAlignment(.trailing)
//          .font(AppTypography.bodySmall)
//  }
//
//  // Numeric input with suffix
//  FormLabeledRow(icon: "percent", label: "Annual rate") {
//      HStack(spacing: AppSpacing.xs) {
//          TextField("0.0", text: $rateText)
//              .keyboardType(.decimalPad)
//              .multilineTextAlignment(.trailing)
//              .font(AppTypography.bodySmall)
//          Text("% / yr")
//              .font(AppTypography.caption)
//              .foregroundStyle(AppColors.textSecondary)
//      }
//  }
//
//  // Toggle with inline hint
//  FormLabeledRow(
//      icon: "arrow.triangle.2.circlepath",
//      label: "Capitalization",
//      hint: "Adds interest to principal each month"
//  ) {
//      Toggle("", isOn: $enabled).labelsHidden()
//  }
//  ```

import SwiftUI

/// A horizontal label-value row for use inside `FormSection(style: .card)`.
///
/// - **icon**: optional SF Symbol name, shown at leading edge without circle background
/// - **label**: persistent label text (always visible — not a placeholder)
/// - **hint**: optional inline help text shown below the row
/// - **trailing**: any view — `TextField`, `Toggle`, `Text`, `Menu`, etc.
///
/// Padding matches `UniversalRow(config: .standard)` so rows are visually
/// consistent when mixing `FormLabeledRow` with `MenuPickerRow` / `DatePickerRow`.
struct FormLabeledRow<TrailingContent: View>: View {

    let icon: String?
    let iconColor: Color
    let label: String
    let hint: String?
    @ViewBuilder let trailing: () -> TrailingContent

    init(
        icon: String? = nil,
        iconColor: Color = AppColors.textSecondary,
        label: String,
        hint: String? = nil,
        @ViewBuilder trailing: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.hint = hint
        self.trailing = trailing
    }

    // Indent hint to align with label text (past icon + spacing).
    private var hintLeadingPad: CGFloat {
        icon != nil ? AppIconSize.md + AppSpacing.md : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppIconSize.sm, weight: .regular))
                        .foregroundStyle(iconColor)
                        .frame(width: AppIconSize.md, height: AppIconSize.md)
                }

                Text(label)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppSpacing.sm)

                trailing()
            }

            if let hint {
                Text(hint)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, hintLeadingPad)
                    .padding(.bottom, AppSpacing.xxs)
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
    }
}

// MARK: - Previews

#Preview("Text Input Row") {
    @Previewable @State var bankName = ""
    @Previewable @State var rateText = ""

    FormSection(header: "Bank Details", style: .card) {
        FormLabeledRow(icon: "building.columns", label: "Bank") {
            TextField("Enter name", text: $bankName)
                .multilineTextAlignment(.trailing)
                .font(AppTypography.bodySmall)
        }

        Divider()

        FormLabeledRow(icon: "percent", label: "Annual rate") {
            HStack(spacing: AppSpacing.xs) {
                TextField("0.0", text: $rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(AppTypography.bodySmall)
                    .frame(maxWidth: 80)
                Text("% / yr")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
    .padding()
}

#Preview("Toggle Row with Hint") {
    @Previewable @State var enabled = true

    FormSection(header: "Schedule", style: .card) {
        FormLabeledRow(
            icon: "arrow.triangle.2.circlepath",
            label: "Capitalization",
            hint: "Interest is added to the principal balance each posting period"
        ) {
            Toggle("", isOn: $enabled)
                .labelsHidden()
        }
    }
    .padding()
}

#Preview("Mixed Row Types") {
    @Previewable @State var bankName = "Halyk Bank"
    @Previewable @State var rateText = "12.5"
    @Previewable @State var enabled = true
    @Previewable @State var postingDay = 15

    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            FormSection(header: "Bank Details", style: .card) {
                FormLabeledRow(icon: "building.columns", label: "Bank") {
                    TextField("Enter name", text: $bankName)
                        .multilineTextAlignment(.trailing)
                        .font(AppTypography.bodySmall)
                }

                Divider()

                FormLabeledRow(icon: "percent", label: "Annual rate") {
                    HStack(spacing: AppSpacing.xs) {
                        TextField("0.0", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(AppTypography.bodySmall)
                            .frame(maxWidth: 80)
                        Text("% / yr")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            FormSection(header: "Schedule", style: .card) {
                MenuPickerRow(
                    icon: "calendar.badge.clock",
                    title: "Posting day",
                    selection: $postingDay,
                    options: (1...31).map { ("\($0)", $0) }
                )

                Divider()

                FormLabeledRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Capitalization",
                    hint: "Adds interest to principal each month"
                ) {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                }
            }
        }
        .padding()
    }
}

#Preview("No Icon") {
    @Previewable @State var notes = ""

    FormSection(style: .card) {
        FormLabeledRow(label: "Notes") {
            TextField("Optional", text: $notes)
                .multilineTextAlignment(.trailing)
                .font(AppTypography.bodySmall)
        }
    }
    .padding()
}
