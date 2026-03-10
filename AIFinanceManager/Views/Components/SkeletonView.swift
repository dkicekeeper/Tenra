//
//  SkeletonView.swift
//  AIFinanceManager
//
//  Skeleton loading base component with shimmer animation (Phase 29, shimmer fixed Phase 30)

import SwiftUI

// MARK: - Shimmer Modifier

/// Overlays a left-to-right shimmer effect on any view — Liquid Glass style.
struct SkeletonShimmerModifier: ViewModifier {
    /// Corner radius forwarded from SkeletonView so the gradient mask matches the shape exactly.
    var cornerRadius: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -2.5
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        // Shimmer highlight opacity: light mode needs stronger white; dark mode needs subtle tint
        let highlightOpacity: CGFloat = colorScheme == .dark
            ? AppAnimation.shimmerOpacityDark
            : AppAnimation.shimmerOpacityLight

        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(highlightOpacity), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
            }
            // Clip to the actual rounded shape — not just the bounding box rectangle
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                guard !isAnimating else { return }
                // Shimmer — декоративное движение. Пропускаем когда включён Reduce Motion.
                // Uses @Environment for live reactivity (user can toggle mid-session).
                guard !reduceMotion else { return }
                isAnimating = true
                withAnimation(
                    .linear(duration: AppAnimation.shimmerDuration).repeatForever(autoreverses: false)
                ) {
                    phase = 1.5
                }
            }
            .onDisappear {
                // Stop the repeatForever animation so it does not conflict
                // with the SkeletonLoadingModifier exit transition (.spring(response: 0.4)).
                // The view is leaving the hierarchy, so no visual reset is needed.
                isAnimating = false
                phase = -0.5
            }
    }
}

extension View {
    /// Adds a left-to-right shimmer animation (Liquid Glass style).
    /// Pass the same `cornerRadius` as the shape so the gradient is clipped correctly.
    func skeletonShimmer(cornerRadius: CGFloat = 0) -> some View {
        modifier(SkeletonShimmerModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - SkeletonView

/// Base skeleton block. Use width: nil to fill available horizontal space.
struct SkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = AppRadius.sm

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppColors.secondaryBackground)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .skeletonShimmer(cornerRadius: cornerRadius)
    }
}

// MARK: - Preview

#Preview("Shimmer") {
    VStack(spacing: AppSpacing.md) {
        SkeletonView(height: 16)
        SkeletonView(width: 200, height: 16)
        SkeletonView(height: 80, cornerRadius: 20)
        SkeletonView(width: 44, height: 44, cornerRadius: 22)
    }
    .padding()
}
