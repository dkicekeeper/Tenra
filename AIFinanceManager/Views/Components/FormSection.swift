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

        /// List style (no background, for use inside List)
        case list

        /// Plain style (no background, no extra padding)
        case plain
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
//                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xs)
            }

            // Content
            Group {
                switch style {
                case .card:
                    VStack(spacing: 0) {
                        content
                    }
                    .cardStyle()

                case .list:
                    VStack(spacing: 0) {
                        content
                    }

                case .plain:
                    content
                }
            }

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
            .padding(AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.md)

        TextField("Amount", text: .constant("9.99"))
            .padding(AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.md)

        HStack {
            Text("Frequency")
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Text("Monthly")
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.md)
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
                    .padding(AppSpacing.md)

                Divider()
                    .padding(.leading, AppSpacing.md)

                TextField("Amount", text: .constant("9.99"))
                    .padding(AppSpacing.md)
            }

            FormSection(
                header: String(localized: "subscription.reminders"),
                footer: "You will be notified before payment",
                style: .card
            ) {
                Toggle("1 day before", isOn: .constant(true))
                    .padding(AppSpacing.md)

                Divider()
                    .padding(.leading, AppSpacing.md)

                Toggle("7 days before", isOn: .constant(false))
                    .padding(AppSpacing.md)
            }
        }
        .padding()
    }
}

#Preview("List Style") {
    List {
        FormSection(
            header: "Account Details",
            style: .list
        ) {
            Text("Row 1")
            Text("Row 2")
            Text("Row 3")
        }

        FormSection(
            header: "Settings",
            footer: "These settings affect your account",
            style: .list
        ) {
            Toggle("Notifications", isOn: .constant(true))
                .padding(.vertical, AppSpacing.lg)
            Toggle("Dark Mode", isOn: .constant(false))
                .padding(.vertical, AppSpacing.lg)
        }
    }
}

#Preview("Plain Style") {
    FormSection(
        header: "Simple Section",
        style: .plain
    ) {
        Text("Item 1")
        Text("Item 2")
        Text("Item 3")
    }
    .padding()
}


#Preview("No Header/Footer") {
    FormSection(style: .card) {
        Text("Content without header or footer")
            .padding(AppSpacing.md)
    }
    .padding()
}
