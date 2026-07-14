//
//  HeroBarPair.swift
//  Tenra
//
//  Full-size was/now bar comparison for insight detail screens (2026-07
//  visual refresh) — hero sibling of the feed's MiniBarPair, same grammar
//  (muted past, tinted fact, translucent+dashed forecast) plus the wow layer:
//  glass surface, colour-matched glow under the CURRENT bar only (the past is
//  context and doesn't glow), staggered grow-in.
//
//  Text-free — the detail header / formula card carries the numbers.
//

import SwiftUI

struct HeroBarPair: View {
    /// The comparison base ("was").
    let previous: Double
    /// The current fact (or projection when `isProjection`).
    let current: Double
    /// Semantic tint of the current bar.
    let color: Color
    /// Renders the current bar as a forecast: translucent fill + dashed outline.
    var isProjection: Bool = false

    var barWidth: CGFloat = 64
    var maxBarHeight: CGFloat = 150
    var animatesOnAppear: Bool = true

    @State private var entered = false
    private var immediate: Bool { !animatesOnAppear || AppAnimation.isReduceMotionEnabled }
    private static let cornerRadius: CGFloat = 10
    /// Bars shorter than this read as "missing" — a zero value stays visible.
    private static let minBarHeight: CGFloat = 10

    private func barHeight(_ value: Double) -> CGFloat {
        let maxValue = max(previous, current, .leastNonzeroMagnitude)
        return max(Self.minBarHeight, maxBarHeight * CGFloat(value / maxValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: AppSpacing.xxl) {
                // "Was" — muted, glowless (the past is context, not signal).
                bar(
                    height: barHeight(previous),
                    delay: 0.05,
                    fill: AnyShapeStyle(AppColors.textSecondary.opacity(0.25))
                )

                // "Now" — glass + colour glow; dashed translucent when projected.
                bar(
                    height: barHeight(current),
                    delay: 0.22,
                    fill: AnyShapeStyle(isProjection ? color.opacity(0.3) : color)
                )
                .overlay(alignment: .bottom) {
                    if isProjection {
                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                            .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .frame(width: barWidth, height: entered ? barHeight(current) : 0)
                            .animation(
                                immediate ? nil : .spring(response: 0.55, dampingFraction: 0.7).delay(0.22),
                                value: entered
                            )
                    }
                }
                .chartGlow(
                    radius: 18,
                    yOffset: 12,
                    opacity: isProjection ? 0.3 : 0.55
                )
            }
            .frame(height: maxBarHeight, alignment: .bottom)

            // Baseline hairline grounding both bars.
            RoundedRectangle(cornerRadius: 0.5)
                .fill(AppColors.textSecondary.opacity(0.2))
                .frame(width: barWidth * 2 + AppSpacing.xxl + AppSpacing.xl * 2, height: 1)
                .padding(.top, AppSpacing.xs)
        }
        .onAppear { entered = true }
    }

    private func bar(height: CGFloat, delay: Double, fill: AnyShapeStyle) -> some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(fill)
            .frame(width: barWidth, height: entered ? height : 0)
            .glassBar(cornerRadius: Self.cornerRadius)
            .animation(
                immediate ? nil : .spring(response: 0.55, dampingFraction: 0.7).delay(delay),
                value: entered
            )
    }
}

// MARK: - Previews

#Preview("Hero pair — spending grew") {
    HeroBarPair(previous: 120_000, current: 168_000, color: AppColors.destructive)
        .padding()
}

#Preview("Hero pair — forecast") {
    HeroBarPair(previous: 140_000, current: 185_000, color: AppColors.destructive, isProjection: true)
        .padding()
}

#Preview("Hero pair — price increase") {
    HeroBarPair(previous: 1_199, current: 9_588, color: AppColors.warning)
        .padding()
}
