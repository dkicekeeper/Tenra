//
//  SectionHeaderView.swift
//  AIFinanceManager
//
//  Unified section header component with consistent styling across the app
//  Replaces: SettingsSectionHeaderView, inline headers, category headers
//

import SwiftUI

/// Unified section header component with 3 style variants
/// - `.default`: Standard list/settings sections (uppercase, secondary color)
/// - `.emphasized`: Form sections with glass background (semibold, primary color)
/// - `.compact`: Picker categories (small, uppercase, secondary color)
struct SectionHeaderView: View {
    let title: String
    /// Optional SF Symbol name shown to the left of the title (accent color).
    /// Currently used only with `.insights` style.
    var systemImage: String? = nil
    let style: Style

    enum Style {
        /// Standard list/settings section header (uppercase, secondary color)
        case `default`

        /// Emphasized form section header (semibold, primary color)
        case emphasized

        /// Compact picker category header (small, uppercase)
        case compact

        /// Insights section title (h3, primary color, optional icon)
        case insights
    }

    init(_ title: String, systemImage: String? = nil, style: Style = .default) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        switch style {
        case .default:
            defaultStyle
        case .emphasized:
            emphasizedStyle
        case .compact:
            compactStyle
        case .insights:
            insightsStyle
        }
    }

    // MARK: - Style Variants

    private var defaultStyle: some View {
        Text(title)
            .font(AppTypography.bodyEmphasis)
            .foregroundStyle(AppColors.textPrimary)
    }

    private var emphasizedStyle: some View {
        Text(title)
            .font(AppTypography.bodySmall)
            .fontWeight(.semibold)
            .foregroundStyle(AppColors.textPrimary)
    }

    private var compactStyle: some View {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
    }

    private var insightsStyle: some View {
        HStack(spacing: AppSpacing.md) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .foregroundStyle(AppColors.accent)
            }
            Text(title)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

// MARK: - Previews

#Preview("Default Style") {
    List {
        Section {
            Text("Setting 1")
            Text("Setting 2")
        } header: {
            SectionHeaderView(String(localized: "settings.general"))
        }

        Section {
            Text("Export")
            Text("Import")
        } header: {
            SectionHeaderView(String(localized: "settings.dataManagement"))
        }
    }
}

#Preview("Emphasized Style") {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
        SectionHeaderView(
            String(localized: "subscription.basicInfo"),
            style: .emphasized
        )
        .padding(.horizontal, AppSpacing.lg)

        VStack(spacing: 0) {
            TextField("Name", text: .constant("Netflix"))
                .padding(AppSpacing.md)

            Divider()

            TextField("Amount", text: .constant("9.99"))
                .padding(AppSpacing.md)
        }
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
    .padding()
}

#Preview("Compact Style") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SectionHeaderView(
                String(localized: "iconPicker.frequentlyUsed"),
                style: .compact
            )
            .padding(.horizontal, AppSpacing.lg)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: AppSpacing.md
            ) {
                ForEach(0..<8) { _ in
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(AppColors.surface)
                        .frame(height: 60)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.vertical, AppSpacing.lg)
    }
}

#Preview("All Styles Comparison") {
    VStack(alignment: .leading, spacing: AppSpacing.xxl) {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Default Style")
                .font(AppTypography.h4)
            SectionHeaderView("Settings Section", style: .default)
        }

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Emphasized Style")
                .font(AppTypography.h4)
            SectionHeaderView("Form Section", style: .emphasized)
        }

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Compact Style")
                .font(AppTypography.h4)
            SectionHeaderView("Category Header", style: .compact)
        }
    }
    .padding()
}
