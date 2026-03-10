//
//  InsightsSkeletonComponents.swift
//  AIFinanceManager
//
//  Per-element skeleton components for InsightsView (Phase 30)
//  Replaces InsightsSkeleton.swift — components are now used independently via .skeletonLoading

import SwiftUI

// MARK: - InsightsSummaryHeaderSkeleton

/// Summary header skeleton: 3 metric columns + health score row.
struct InsightsSummaryHeaderSkeleton: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // 3 metric columns (Income / Expenses / Net Flow)
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: AppSpacing.xs) {
                        SkeletonView(height: 11, cornerRadius: AppRadius.xs)
                        SkeletonView(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
                .opacity(0.3)

            // Health score row
            HStack {
                SkeletonView(width: 150, height: 13, cornerRadius: AppRadius.compact)
                Spacer()
                SkeletonView(width: 64, height: 22, cornerRadius: AppRadius.md)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.groupedBackgroundSecondary)
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .accessibilityHidden(true)
    }
}

// MARK: - InsightsFilterCarouselSkeleton

/// Filter carousel skeleton: 4 chip placeholders.
struct InsightsFilterCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonView(width: 70, height: 30, cornerRadius: AppRadius.xl)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - InsightCardSkeleton

/// Single insight card skeleton: icon circle + 3 text lines + trailing chart rect.
struct InsightCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon circle
            SkeletonView(width: 40, height: 40, cornerRadius: AppRadius.circle)

            // Text content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 160, height: 13)
                SkeletonView(width: 100, height: 11, cornerRadius: AppRadius.xs)
                SkeletonView(width: 120, height: 19, cornerRadius: AppRadius.sm)
            }

            Spacer()

            // Chart placeholder
            SkeletonView(width: AppIconSize.budgetRing, height: AppIconSize.xxxl, cornerRadius: AppRadius.sm)
        }
        .padding(AppSpacing.md)
        .background(AppColors.groupedBackgroundSecondary)
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Insights Skeleton Components") {
    VStack(spacing: AppSpacing.lg) {
        InsightsSummaryHeaderSkeleton()
        InsightsFilterCarouselSkeleton()
        InsightCardSkeleton()
    }
    .padding()
    .background(AppColors.groupedBackground)
}
