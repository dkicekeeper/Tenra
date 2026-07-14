//
//  LinearProgressBar.swift
//  Tenra
//
//  Reusable horizontal budget progress bar with over-budget state.
//  Extracted from InsightsCardView and InsightDetailView (Phase 26).
//

import SwiftUI

/// Horizontal progress bar for budget utilisation.
///
/// Visual model:
/// - `percentage ≤ 100` → single segment in `color`, width = `percentage / 100` of bar.
/// - `percentage > 100` → bar fills full width split into two segments:
///   the leading `100 / percentage` portion in `color` (the original budget),
///   the trailing `(percentage - 100) / percentage` portion in `AppColors.destructive`
///   (the overshoot). Higher overshoot ⇒ larger red zone, so magnitude is visible
///   instead of a flat 100 % red bar at any percentage above 100.
/// - `projectedPercentage` set (forecast mode, 2026-07 visual refresh) → the scale
///   becomes `max(projected, 110)` so the 100% LIMIT TICK sits inside the track:
///   solid `color` up to `percentage` (the fact), translucent `color` from there to
///   the projection (forecast grammar: translucent = not yet real), destructive
///   tick at the limit. The projection visibly crossing the tick IS the message.
///
/// - Parameter percentage: 0–100+ (raw, not clamped)
/// - Parameter isOverBudget: true → renders the destructive overshoot segment
/// - Parameter color: brand color for the category (the in-budget portion)
/// - Parameter height: bar height in points (default 8; InsightsCardView uses 6)
/// - Parameter projectedPercentage: end-of-period projection (enables forecast mode)
struct LinearProgressBar: View {
    let percentage: Double
    let isOverBudget: Bool
    let color: Color
    var height: CGFloat = 8
    /// Sweep-from-zero entrance. Disable in lazy lists/feeds — `onAppear`
    /// re-fires on every row re-materialisation during scroll.
    var animatesOnAppear: Bool = true
    /// End-of-period projected consumption (0–100+); enables forecast mode.
    var projectedPercentage: Double? = nil

    @State private var displayPercentage: Double = 0
    /// Reduce-Motion-aware (nil under Reduce Motion → instant jump, no sweep).
    private var fillAnimation: Animation? { AppAnimation.progressFillAnimation }

    private var baseRatio: Double {
        if let projected = projectedPercentage {
            let scale = max(projected, 110)
            return min(max(displayPercentage, 0), scale) / scale
        }
        if isOverBudget {
            return displayPercentage > 0 ? min(100.0 / displayPercentage, 1.0) : 0.0
        } else {
            return min(max(displayPercentage, 0), 100) / 100.0
        }
    }

    private var overshootRatio: Double {
        guard projectedPercentage == nil else { return 0 }
        guard isOverBudget, displayPercentage > 100 else { return 0 }
        return 1.0 - min(100.0 / displayPercentage, 1.0)
    }

    /// Forecast-mode translucent segment: fact → projection, as a track fraction.
    private var projectionRatio: Double {
        guard let projected = projectedPercentage, projected > displayPercentage else { return 0 }
        let scale = max(projected, 110)
        return (min(projected, scale) - max(displayPercentage, 0)) / scale
    }

    /// Forecast-mode limit tick position (the 100% mark), as a track fraction.
    private var limitRatio: Double? {
        guard let projected = projectedPercentage else { return nil }
        return 100 / max(projected, 110)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(AppColors.bgMuted)
                .frame(maxWidth: .infinity)
                .frame(height: height)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * baseRatio)
                    if overshootRatio > 0 {
                        Rectangle()
                            .fill(AppColors.destructive)
                            .frame(width: geo.size.width * overshootRatio)
                    }
                    if projectionRatio > 0 {
                        Rectangle()
                            .fill(color.opacity(0.3))
                            .frame(width: geo.size.width * projectionRatio)
                    }
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))

            // Limit tick — drawn OVER the segments, overshooting the track
            // vertically so it reads as a marker, not a divider.
            if let limitRatio {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1.25)
                        .fill(AppColors.destructive)
                        .frame(width: 2.5, height: height + 8)
                        .position(x: geo.size.width * limitRatio, y: height / 2)
                }
                .frame(height: height)
            }
        }
        .animation(AppAnimation.progressFillAnimation, value: isOverBudget)
        .onAppear {
            if animatesOnAppear {
                withAnimation(fillAnimation) { displayPercentage = percentage }
            } else {
                displayPercentage = percentage
            }
        }
        .onChange(of: percentage) { _, newValue in
            withAnimation(fillAnimation) { displayPercentage = newValue }
        }
    }
}

// MARK: - Previews

#Preview("Normal") {
    VStack(spacing: AppSpacing.md) {
        LinearProgressBar(percentage: 65, isOverBudget: false, color: .blue)
        LinearProgressBar(percentage: 95, isOverBudget: false, color: .green)
        LinearProgressBar(percentage: 120, isOverBudget: true, color: .orange)
        LinearProgressBar(percentage: 200, isOverBudget: true, color: .orange)
        LinearProgressBar(percentage: 350, isOverBudget: true, color: .orange)
    }
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (height 6)") {
    LinearProgressBar(percentage: 72, isOverBudget: false, color: .purple, height: 6)
        .screenPadding()
}

#Preview("Forecast mode (projection + limit tick)") {
    VStack(spacing: AppSpacing.lg) {
        LinearProgressBar(percentage: 55, isOverBudget: false, color: .indigo, height: 6, projectedPercentage: 130)
        LinearProgressBar(percentage: 80, isOverBudget: false, color: .orange, height: 6, projectedPercentage: 105)
        LinearProgressBar(percentage: 30, isOverBudget: false, color: .teal, height: 6, projectedPercentage: 220)
    }
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
