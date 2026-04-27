//
//  OnboardingPageContainer.swift
//  Tenra
//
//  Shared layout for onboarding data-collection steps:
//  progress bar (top), title + subtitle, body content, primary CTA pinned at the bottom.
//

import SwiftUI

struct OnboardingPageContainer<Content: View>: View {
    let progressStep: Int            // 1, 2, or 3
    let title: String
    let subtitle: String?
    let primaryButtonTitle: String
    let primaryButtonEnabled: Bool
    let onPrimaryTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(totalSteps: 3, currentStep: progressStep)
                .padding(.top, AppSpacing.lg)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button(action: onPrimaryTap) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!primaryButtonEnabled)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
    }
}
