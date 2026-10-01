//
//  StatusIndicatorBadge.swift
//  Tenra
//
//  Maps Tenra's subscription status to DesignKit's EntityStatus
//  (StatusIndicatorBadge itself lives in DesignKit).
//

import SwiftUI

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
