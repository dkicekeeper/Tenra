//
//  OnboardingWelcomePage.swift
//  Tenra
//

import SwiftUI

struct OnboardingWelcomePage: View {
    let sfSymbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: sfSymbol)
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(AppColors.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
