//
//  ActionSettingsRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//  Migrated to UniversalRow architecture - 2026-02-16
//

import SwiftUI

/// Props-based action row for Settings
/// Single Responsibility: Display action button with icon, title, and optional destructive styling
/// Now built on top of UniversalRow for consistency
struct ActionSettingsRow: View {
    // MARK: - Props

    let icon: String
    let title: String
    let iconColor: Color?
    let titleColor: Color?
    let isDestructive: Bool
    let action: () -> Void

    // MARK: - Initializer

    init(
        icon: String,
        title: String,
        iconColor: Color? = nil,
        titleColor: Color? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.titleColor = titleColor
        self.isDestructive = isDestructive
        self.action = action
    }

    // MARK: - Computed Properties

    private var resolvedIconColor: Color {
        iconColor ?? (isDestructive ? AppColors.destructive : AppColors.accent)
    }

    private var resolvedTitleColor: Color {
        titleColor ?? (isDestructive ? AppColors.destructive : AppColors.textPrimary)
    }

    // MARK: - Body

    var body: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol(icon, color: resolvedIconColor, size: AppIconSize.md)
        ) {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(resolvedTitleColor)
        } trailing: {
            EmptyView()
        }
        .actionRow(role: isDestructive ? .destructive : nil, action: action)
    }
}

// MARK: - Preview

#Preview {
    List {
        ActionSettingsRow(
            icon: "square.and.arrow.up",
            title: String(localized: "settings.exportData")
        ) {
        }

        ActionSettingsRow(
            icon: "square.and.arrow.down",
            title: String(localized: "settings.importData")
        ) {
        }

        ActionSettingsRow(
            icon: "arrow.triangle.2.circlepath",
            title: String(localized: "settings.recalculateBalances"),
            iconColor: AppColors.warning,
            titleColor: AppColors.warning
        ) {
        }

        ActionSettingsRow(
            icon: "trash",
            title: String(localized: "settings.resetData"),
            isDestructive: true
        ) {
        }
    }
}
