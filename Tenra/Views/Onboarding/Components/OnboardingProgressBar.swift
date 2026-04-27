//
//  OnboardingProgressBar.swift
//  Tenra
//
//  3-dot progress indicator for the data-collection portion of onboarding.
//

import SwiftUI

struct OnboardingProgressBar: View {
    let totalSteps: Int
    let currentStep: Int  // 1-based

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index < currentStep ? AppColors.accent : AppColors.textSecondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .animation(AppAnimation.contentSpring, value: currentStep)
    }
}
