//
//  SectionHeaderView.swift
//  AIFinanceManager
//
//  Unified section header component with consistent styling across the app
//  Replaces: SettingsSectionHeaderView, inline headers, category headers
//

import SwiftUI

/// Unified section header component with 3 style variants
/// - `.default`: Standard section header (bodyEmphasis, primary color). Used in forms, date groups, cards.
/// - `.compact`: Small uppercase label (bodySmall, secondary color, with horizontal padding). Used in filters, pickers.
/// - `.large`: Page-level section title (h3, primary color, optional icon, with horizontal padding). Used in insights.
struct SectionHeaderView: View {
    let title: String
    /// Optional SF Symbol name shown to the left of the title (accent color).
    /// Currently used only with `.large` style.
    var systemImage: String? = nil
    let style: Style

    enum Style {
        /// Standard section header (bodyEmphasis, primary color)
        case `default`

        /// Small uppercase label with horizontal padding (bodySmall, secondary color)
        case compact

        /// Page-level section title with horizontal padding (h3, primary color, optional icon)
        case large
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
        case .compact:
            compactStyle
        case .large:
            largeStyle
        }
    }

    // MARK: - Style Variants

    private var defaultStyle: some View {
        Text(title)
            .font(AppTypography.bodyEmphasis)
            .foregroundStyle(AppColors.textPrimary)
    }

    private var compactStyle: some View {
        Text(title)
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
    }

    private var largeStyle: some View {
        HStack(spacing: AppSpacing.md) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .foregroundStyle(AppColors.accent)
            }
            Text(title)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.lg)
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

#Preview("Compact Style") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SectionHeaderView(
                String(localized: "iconPicker.frequentlyUsed"),
                style: .compact
            )

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

#Preview("Large Style") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SectionHeaderView("Cash Flow Trend", style: .large)
            SectionHeaderView("Monthly Breakdown", systemImage: "chart.bar", style: .large)
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
            Text("Compact Style")
                .font(AppTypography.h4)
            SectionHeaderView("Category Header", style: .compact)
        }

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Large Style")
                .font(AppTypography.h4)
            SectionHeaderView("Insights Section", style: .large)
        }
    }
    .padding()
}
