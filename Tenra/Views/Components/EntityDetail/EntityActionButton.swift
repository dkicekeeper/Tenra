//
//  EntityActionButton.swift
//  Tenra
//
//  Custom action-bar button used by `EntityDetailScaffold` (Account / Category /
//  Deposit / Loan / Subscription detail). Replaces the native `.borderedProminent`
//  / `.bordered` pair — those don't match the app's visual language (icon-above-text,
//  card background, accent tint).
//
//  Layout: centered icon on top, label below (max 2 lines). Expands to fill its
//  parent HStack so multiple buttons share horizontal space equally.
//

import SwiftUI

struct EntityActionButton: View {
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    private var tint: Color {
        role == .destructive ? AppColors.destructive : AppColors.accent
    }

    var body: some View {
        Button(role: role, action: {
            HapticManager.light()
            action()
        }) {
            VStack(spacing: AppSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: AppIconSize.lg, weight: .semibold))
                        .frame(width: AppIconSize.lg, height: AppIconSize.lg)
                }
                Text(title)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.sm)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(title)
    }
}


// MARK: - Previews

#Preview("Single") {
    EntityActionButton(
        title: "Add Transaction",
        systemImage: "plus",
        action: {}
    )
    .padding()
}

#Preview("Row — two actions") {
    HStack(spacing: AppSpacing.md) {
        EntityActionButton(title: "Top Up", systemImage: "arrow.down.circle.fill", action: {})
        EntityActionButton(title: "Withdraw", systemImage: "arrow.up.circle.fill", action: {})
    }
    .padding()
}

#Preview("Row — three actions") {
    HStack(spacing: AppSpacing.md) {
        EntityActionButton(title: "Transfer", systemImage: "arrow.left.arrow.right", action: {})
        EntityActionButton(title: "Edit", systemImage: "pencil", action: {})
        EntityActionButton(title: "Link Payment", systemImage: "link", action: {})
    }
    .padding()
}

#Preview("Long labels (2 lines)") {
    HStack(spacing: AppSpacing.md) {
        EntityActionButton(title: "Досрочное погашение", systemImage: "bolt.fill", action: {})
        EntityActionButton(title: "Связать платежи", systemImage: "link", action: {})
    }
    .padding()
}

#Preview("Destructive") {
    HStack(spacing: AppSpacing.md) {
        EntityActionButton(title: "Edit", systemImage: "pencil", action: {})
        EntityActionButton(title: "Delete", systemImage: "trash", role: .destructive, action: {})
    }
    .padding()
}
