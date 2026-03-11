//
//  SkeletonLoadingModifier.swift
//  AIFinanceManager
//
//  Universal per-element skeleton loading modifier (Phase 30)

import SwiftUI

// MARK: - SkeletonLoadingModifier

/// Universal ViewModifier — shows skeleton when isLoading, transitions to real content when ready.
/// Usage: anyView.skeletonLoading(isLoading: flag) { SkeletonShape() }
struct SkeletonLoadingModifier<S: View>: ViewModifier {
    let isLoading: Bool
    @ViewBuilder let skeleton: () -> S

    func body(content: Content) -> some View {
        Group {
            if isLoading {
                skeleton()
                    .transition(.opacity.combined(with: .scale(AppAnimation.skeletonScale, anchor: .center)))
            } else {
                content
                    .transition(.opacity.combined(with: .scale(AppAnimation.skeletonScale, anchor: .center)))
            }
        }
        .animation(.spring(response: AppAnimation.skeletonResponse), value: isLoading)
    }
}

extension View {
    /// Replaces this view with `skeleton()` while `isLoading` is true.
    /// Transitions smoothly to real content once loading completes.
    func skeletonLoading<S: View>(
        isLoading: Bool,
        @ViewBuilder skeleton: @escaping () -> S
    ) -> some View {
        modifier(SkeletonLoadingModifier(isLoading: isLoading, skeleton: skeleton))
    }
}

// MARK: - Preview

#Preview("SkeletonLoading transitions") {
    VStack(spacing: AppSpacing.lg) {
        Text("isLoading: true → skeleton shown")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        SkeletonView(height: 20)
            .skeletonLoading(isLoading: true) {
                SkeletonView(height: 20)
            }

        Text("isLoading: false → content shown")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        Text("Real content here")
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity)
            .background(AppColors.surface)
            .clipShape(.rect(cornerRadius: AppRadius.sm))
            .skeletonLoading(isLoading: false) {
                SkeletonView(height: 44)
            }
    }
    .padding(AppSpacing.lg)
    .background(AppColors.backgroundPrimary)
}
