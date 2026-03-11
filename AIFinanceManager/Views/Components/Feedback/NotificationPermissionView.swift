//
//  NotificationPermissionView.swift
//  AIFinanceManager
//
//  Created on 2026-02-14
//  Purpose: Request notification permissions for subscription reminders
//

import SwiftUI

struct NotificationPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    let onAllow: () async -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            // Icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: AppIconSize.coin))
                .foregroundStyle(AppColors.accent)
                .padding(.bottom, AppSpacing.md)

            // Title
            Text(String(localized: "notification.permission.title"))
                .font(AppTypography.h2)
                .multilineTextAlignment(.center)

            // Description
            Text(String(localized: "notification.permission.description"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            Spacer()

            // Buttons
            VStack(spacing: AppSpacing.md) {
                Button {
                    HapticManager.light()
                    Task {
                        await onAllow()
                        dismiss()
                    }
                } label: {
                    Text(String(localized: "notification.permission.allow"))
                        .font(AppTypography.body)
                        .bold()
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accent)
                        .clipShape(.rect(cornerRadius: AppRadius.md))
                }

                Button {
                    HapticManager.light()
                    onSkip()
                    dismiss()
                } label: {
                    Text(String(localized: "notification.permission.skip"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        }
        .padding(.top, AppSpacing.xl)
    }
}

#Preview {
    NotificationPermissionView(
        onAllow: { },
        onSkip: { }
    )
}
