//
//  HeroMilestoneGauge.swift
//  Tenra
//
//  Full-size segmented milestone scale for insight detail screens (2026-07
//  visual refresh) — hero sibling of the feed's MiniMilestoneGauge (emergency
//  fund months). Same grammar (filled = fact, muted = remainder, tick =
//  target) plus the wow layer: glass segments, colour glow under the filled
//  run, a left-to-right fill wave, target tick landing after the wave.
//
//  Text-free — the detail header / formula card carries the numbers.
//

import SwiftUI

struct HeroMilestoneGauge: View {
    /// Measured value in milestone units (e.g. 2.4 months).
    let value: Double
    /// Target milestone the tick marks (e.g. 3 months).
    let target: Double
    /// Total segments on the scale (e.g. 6 months).
    let maxValue: Double
    /// Fill tint (severity).
    let color: Color

    var segmentHeight: CGFloat = 22
    var animatesOnAppear: Bool = true

    @State private var entered = false
    private var immediate: Bool { !animatesOnAppear || AppAnimation.isReduceMotionEnabled }

    private static let cornerRadius: CGFloat = 6
    private static let segmentGap: CGFloat = 6
    private static let tickOvershoot: CGFloat = 9
    private static let waveStep: Double = 0.08

    private var segments: Int { max(1, Int(maxValue.rounded())) }
    private var clamped: Double { min(max(value, 0), maxValue) }

    var body: some View {
        GeometryReader { geo in
            let gapTotal = Self.segmentGap * CGFloat(segments - 1)
            let segmentWidth = (geo.size.width - gapTotal) / CGFloat(segments)

            ZStack(alignment: .leading) {
                // Muted base row.
                segmentRow(segmentWidth: segmentWidth) { _ in
                    AnyShapeStyle(AppColors.textSecondary.opacity(0.15))
                }

                // Filled run — glass + glow, revealed as a left-to-right wave.
                segmentRow(segmentWidth: segmentWidth, fillFractionOf: clamped) { _ in
                    AnyShapeStyle(color)
                }
                .chartGlow(radius: 14, yOffset: 8)

                // Target tick on the boundary after the `target`-th segment,
                // landing once the wave has passed it.
                tick(segmentWidth: segmentWidth)
                    .materialize(
                        delay: Double(min(target, clamped)) * Self.waveStep + 0.45,
                        animatesOnAppear: animatesOnAppear
                    )
            }
        }
        .frame(height: segmentHeight + Self.tickOvershoot * 2)
        .onAppear { entered = true }
    }

    /// A row of segments. With `fillFractionOf` set, segment `i` shows only its
    /// covered fraction of `value` (the in-progress segment fills partially) and
    /// enters with a staggered wave.
    private func segmentRow(
        segmentWidth: CGFloat,
        fillFractionOf coveredValue: Double? = nil,
        style: @escaping (Int) -> AnyShapeStyle
    ) -> some View {
        HStack(spacing: Self.segmentGap) {
            ForEach(0..<segments, id: \.self) { i in
                let fraction: Double = {
                    guard let coveredValue else { return 1 }
                    return min(max(coveredValue - Double(i), 0), 1)
                }()
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(style(i))
                    .frame(width: segmentWidth * CGFloat(fraction), height: segmentHeight)
                    .glassBar(cornerRadius: Self.cornerRadius)
                    .opacity(coveredValue == nil || entered ? 1 : 0)
                    .scaleEffect(
                        coveredValue == nil || entered ? 1 : 0.6,
                        anchor: .leading
                    )
                    .animation(
                        coveredValue == nil || immediate
                            ? nil
                            : .spring(response: 0.45, dampingFraction: 0.7).delay(Double(i) * Self.waveStep),
                        value: entered
                    )
                    // Keep the HStack slot at full segment width so partial
                    // fills don't shift later segments left.
                    .frame(width: segmentWidth, alignment: .leading)
            }
        }
        .frame(height: segmentHeight + Self.tickOvershoot * 2)
    }

    private func tick(segmentWidth: CGFloat) -> some View {
        let boundary = min(max(target, 0), maxValue)
        let x = CGFloat(boundary) * (segmentWidth + Self.segmentGap) - Self.segmentGap / 2
        return Capsule()
            .fill(AppColors.textSecondary.opacity(0.7))
            .frame(width: 3, height: segmentHeight + Self.tickOvershoot * 2)
            .offset(x: x - 1.5)
    }
}

// MARK: - Previews

#Preview("Hero milestones — 2.4 of 6, target 3") {
    HeroMilestoneGauge(value: 2.4, target: 3, maxValue: 6, color: AppColors.warning)
        .padding()
}

#Preview("Hero milestones — 5.2 of 6 (healthy)") {
    HeroMilestoneGauge(value: 5.2, target: 3, maxValue: 6, color: AppColors.success)
        .padding()
}

#Preview("Hero milestones — 0.6 (critical)") {
    HeroMilestoneGauge(value: 0.6, target: 3, maxValue: 6, color: AppColors.destructive)
        .padding()
}
