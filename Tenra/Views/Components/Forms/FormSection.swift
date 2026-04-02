//
//  FormSection.swift
//  AIFinanceManager
//
//  Reusable wrapper for form sections with header/footer support
//  Reduces boilerplate in edit views
//

import SwiftUI

/// Form section container with optional header and footer
/// Provides consistent styling for form groups with automatic dividers
struct FormSection<Content: View>: View {
    let header: String?
    let footer: String?
    let style: Style
    @ViewBuilder let content: Content

    enum Style {
        /// Card style with background and rounded corners
        case card
    }

    init(
        header: String? = nil,
        footer: String? = nil,
        style: Style = .card,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.footer = footer
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header
            if let header = header {
                HStack {
                    SectionHeaderView(header, style: .default)
                    Spacer()
                }
            }

            // Content
            VStack(spacing: 0) {
                content
            }
            .cardStyle()

            // Footer
            if let footer = footer {
                Text(footer)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xs)
            }
        }
    }
}

// MARK: - Previews

#Preview("Card Style") {
    FormSection(
        header: String(localized: "subscription.basicInfo"),
        footer: "This is a helpful footer text",
        style: .card
    ) {
        TextField("Name", text: .constant("Netflix"))
            .padding(AppSpacing.lg)

        Divider()
            .padding(.leading, AppSpacing.lg)

        TextField("Amount", text: .constant("9.99"))
            .padding(AppSpacing.lg)

        Divider()
            .padding(.leading, AppSpacing.lg)

        HStack {
            Text("Frequency")
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Text("Monthly")
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.lg)
    }
    .padding()
}

#Preview("Multiple Sections") {
    ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            FormSection(
                header: String(localized: "subscription.basicInfo"),
                style: .card
            ) {
                TextField("Name", text: .constant("Netflix"))
                    .padding(AppSpacing.lg)

                Divider()
                    .padding(.leading, AppSpacing.lg)

                TextField("Amount", text: .constant("9.99"))
                    .padding(AppSpacing.lg)
            }

            FormSection(
                header: String(localized: "subscription.reminders"),
                footer: "You will be notified before payment",
                style: .card
            ) {
                Toggle("1 day before", isOn: .constant(true))
                    .padding(AppSpacing.lg)

                Divider()
                    .padding(.leading, AppSpacing.lg)

                Toggle("7 days before", isOn: .constant(false))
                    .padding(AppSpacing.lg)
            }
        }
        .padding()
    }
}


#Preview("No Header/Footer") {
    FormSection(style: .card) {
        Text("Content without header or footer")
            .padding(AppSpacing.lg)
    }
    .padding()
}
