//
//  StatusIndicatorBadge.swift
//  AIFinanceManager
//
//  Phase 33.2: Extracted from SubscriptionCard to be reusable across the app.
//  Shows a coloured SF Symbol icon for a given entity status.
//

import SwiftUI

// MARK: - EntityStatus

/// Unified status model for entities that have an active / paused / archived lifecycle.
/// Add new cases here as the domain grows — the badge adapts automatically.
enum EntityStatus {
    case active
    case paused
    case archived
    case pending

    // MARK: Display

    var iconName: String {
        switch self {
        case .active:   return "checkmark.circle.fill"
        case .paused:   return "pause.circle.fill"
        case .archived: return "archive.circle.fill"
        case .pending:  return "clock.badge.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .active:   return AppColors.statusActive
        case .paused:   return AppColors.statusPaused
        case .archived: return AppColors.statusArchived
        case .pending:  return AppColors.accent
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .active:   return "status.active"
        case .paused:   return "status.paused"
        case .archived: return "status.archived"
        case .pending:  return "status.pending"
        }
    }
}

// MARK: - StatusIndicatorBadge

/// A single SF Symbol icon that communicates entity status through colour and shape.
///
/// Use inside a row, card, or chip where you need a compact visual status signal.
///
/// ```swift
/// StatusIndicatorBadge(status: .active, font: AppTypography.h4)
/// StatusIndicatorBadge(status: .paused, iconSize: AppIconSize.md)
/// ```
struct StatusIndicatorBadge: View {
    let status: EntityStatus

    /// Font size applied to the SF Symbol via `.font()`.
    /// Provide either `font` (semantic) or `iconSize` (explicit points), not both.
    var font: Font = AppTypography.h4

    var body: some View {
        Image(systemName: status.iconName)
            .font(font)
            .foregroundStyle(status.tintColor)
            .accessibilityLabel(status.accessibilityLabel)
    }
}

// MARK: - RecurringSubscriptionStatus bridge

extension RecurringSeries {
    /// Maps the domain subscription status to a generic `EntityStatus` for display.
    var entityStatus: EntityStatus? {
        switch subscriptionStatus {
        case .active:   return .active
        case .paused:   return .paused
        case .archived: return .archived
        case .none:     return nil
        }
    }
}

// MARK: - Preview

#Preview("All Status Variants") {
    HStack(spacing: AppSpacing.xl) {
        ForEach([EntityStatus.active, .paused, .archived, .pending], id: \.iconName) { status in
            VStack(spacing: AppSpacing.xs) {
                StatusIndicatorBadge(status: status, font: AppTypography.h3)
                Text(status.accessibilityLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
