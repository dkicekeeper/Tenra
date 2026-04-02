//
//  EmptyCardView.swift
//  AIFinanceManager
//
//  Universal card component for section empty states.
//  Shows a section title + compact empty message, optionally tappable.
//

import SwiftUI

/// Card with a section header and compact empty state.
///
/// Use when a home-screen section has no data yet.
/// Pass `action` to make the entire card tappable (adds account, category, etc.).
///
/// ```swift
/// EmptyCardView(
///     sectionTitle: String(localized: "accounts.title"),
///     emptyTitle: String(localized: "emptyState.noAccounts"),
///     action: { showingAddAccount = true }
/// )
/// .screenPadding()
/// ```
struct EmptyCardView: View {

    let sectionTitle: String
    let emptyTitle: String
    var action: (@Sendable () -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: {
                HapticManager.light()
                action()
            }) {
                cardContent
            }
            .buttonStyle(.bounce)
            .accessibilityLabel("\(sectionTitle). \(emptyTitle)")
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(sectionTitle)
                .font(AppTypography.h3)
                .foregroundStyle(.primary)

            EmptyStateView(
                title: emptyTitle,
                style: .compact
            )
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Tappable") {
    EmptyCardView(
        sectionTitle: String(localized: "accounts.title"),
        emptyTitle: String(localized: "emptyState.noAccounts"),
        action: {}
    )
    .screenPadding()
}

#Preview("Non-tappable") {
    EmptyCardView(
        sectionTitle: String(localized: "analytics.history"),
        emptyTitle: String(localized: "emptyState.noTransactions")
    )
    .screenPadding()
}
