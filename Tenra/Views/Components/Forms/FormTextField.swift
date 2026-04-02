//
//  FormTextField.swift
//  AIFinanceManager
//
//  Enhanced text field with error states, help text, and validation
//  Replaces DescriptionTextField with more features
//

import SwiftUI

/// Enhanced text field for forms with error/help states and multiple styles.
/// Supports single-line and multiline variants.
///
/// **States supported:**
/// - Normal (idle), Focused (accent border + tinted bg), Filled (has text),
///   Error (red border + message), Disabled (dimmed, non-interactive),
///   Help (info text below)
struct FormTextField: View {
    @Binding var text: String
    let placeholder: String
    let style: Style
    let keyboardType: UIKeyboardType
    let errorMessage: String?
    let helpText: String?
    let isDisabled: Bool
    @FocusState private var isFocused: Bool

    enum Style {
        /// Standard single-line text field with filled background
        case standard

        /// Multiline text field with line limits and filled background
        case multiline(min: Int, max: Int)
    }

    init(
        text: Binding<String>,
        placeholder: String,
        style: Style = .standard,
        keyboardType: UIKeyboardType = .default,
        errorMessage: String? = nil,
        helpText: String? = nil,
        isDisabled: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.style = style
        self.keyboardType = keyboardType
        self.errorMessage = errorMessage
        self.helpText = helpText
        self.isDisabled = isDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            fieldArea
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.45 : 1)

            if let error = errorMessage {
                errorLabel(error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let help = helpText, errorMessage == nil {
                Text(help)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.fastAnimation, value: isFocused)
        .animation(AppAnimation.fastAnimation, value: errorMessage != nil)
    }

    // MARK: - Field Area

    @ViewBuilder
    private var fieldArea: some View {
        switch style {
        case .standard:
            standardField
                .padding(AppSpacing.lg)
                .background(backgroundForState)
                .clipShape(.rect(cornerRadius: AppRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .stroke(borderForState, lineWidth: borderWidth)
                )

        case .multiline(let min, let max):
            multilineField(min: min, max: max)
                .padding(AppSpacing.lg)
                .background(backgroundForState)
                .clipShape(.rect(cornerRadius: AppRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .stroke(borderForState, lineWidth: borderWidth)
                )
        }
    }

    // MARK: - Field Variants

    private var standardField: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .focused($isFocused)
            .font(AppTypography.body)
    }

    private func multilineField(min: Int, max: Int) -> some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(min...max)
            .focused($isFocused)
            .font(AppTypography.body)
    }

    // MARK: - Styling Helpers

    private var backgroundForState: Color {
        if isDisabled {
            return AppColors.surface.opacity(0.3)
        } else if errorMessage != nil {
            return AppColors.destructive.opacity(0.05)
        } else if isFocused {
            return AppColors.accent.opacity(0.04)
        } else {
            return AppColors.surface.opacity(0.5)
        }
    }

    private var borderForState: Color {
        if errorMessage != nil {
            return AppColors.destructive.opacity(0.45)
        } else if isFocused {
            return AppColors.accent.opacity(0.55)
        } else {
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        errorMessage != nil || isFocused ? 1 : 0
    }

    // MARK: - Sub-views

    private func errorLabel(_ message: String) -> some View {
        Label {
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.destructive)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.destructive)
        }
    }
}

// MARK: - Previews

#Preview("Standard Style") {
    @Previewable @State var text = ""

    return VStack(spacing: AppSpacing.lg) {
        FormTextField(
            text: $text,
            placeholder: "Enter your name"
        )

        FormTextField(
            text: $text,
            placeholder: "Email address",
            keyboardType: .emailAddress,
            helpText: "We'll never share your email"
        )
    }
    .padding()
}

#Preview("With Error") {
    @Previewable @State var text = "invalid"

    return FormTextField(
        text: $text,
        placeholder: "Amount",
        keyboardType: .decimalPad,
        errorMessage: "Please enter a valid amount"
    )
    .padding()
}

#Preview("Multiline") {
    @Previewable @State var text = ""

    return VStack(spacing: AppSpacing.lg) {
        FormTextField(
            text: $text,
            placeholder: "Description",
            style: .multiline(min: 3, max: 6)
        )

        FormTextField(
            text: $text,
            placeholder: "Notes",
            style: .multiline(min: 2, max: 4),
            helpText: "Add any additional notes here"
        )
    }
    .padding()
}


#Preview("All States") {
    @Previewable @State var normal = ""
    @Previewable @State var filled = "Some filled text"
    @Previewable @State var withHelp = ""
    @Previewable @State var withError = "bad input"
    @Previewable @State var disabled = "Can't edit this"
    @Previewable @State var disabledError = "bad"

    return ScrollView {
        VStack(spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Normal (idle)")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(text: $normal, placeholder: "Normal state")
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Filled (has text, unfocused)")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(text: $filled, placeholder: "Filled state")
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Focused — tap to trigger (accent border + tinted bg)")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(text: $normal, placeholder: "Tap me to see focused state")
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("With Help Text")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(
                    text: $withHelp,
                    placeholder: "Field with help",
                    helpText: "This is some helpful information"
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Error")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(
                    text: $withError,
                    placeholder: "Field with error",
                    errorMessage: "This field has an error"
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Disabled")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(
                    text: $disabled,
                    placeholder: "Disabled field",
                    isDisabled: true
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Disabled + Error")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                FormTextField(
                    text: $disabledError,
                    placeholder: "Disabled with error",
                    errorMessage: "This error is shown",
                    isDisabled: true
                )
            }
        }
        .padding()
    }
}

#Preview("In Form Context") {
    @Previewable @State var name = ""
    @Previewable @State var amount = ""
    @Previewable @State var description = ""

    return ScrollView {
        VStack(spacing: 0) {
            FormSection(
                header: String(localized: "subscription.basicInfo"),
                style: .card
            ) {
                FormTextField(
                    text: $name,
                    placeholder: String(localized: "subscription.namePlaceholder")
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                FormTextField(
                    text: $amount,
                    placeholder: "0.00",
                    keyboardType: .decimalPad,
                    helpText: "Enter subscription amount"
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                FormTextField(
                    text: $description,
                    placeholder: "Description (optional)",
                    style: .multiline(min: 2, max: 4)
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
        }
        .padding()
    }
}
