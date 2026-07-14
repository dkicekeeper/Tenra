//
//  MiniMilestoneGauge.swift
//  Tenra
//
//  Canvas-based segmented milestone scale for insight feed cards (2026-07
//  visual refresh). Used where the metric is progress toward a DISCRETE
//  milestone — emergency fund months (target 3 of 6). Discrete segments answer
//  "how many months" more precisely than a continuous arc or bar would.
//
//  Visual grammar (docs/domains/charts.md §Insight mini-visuals):
//  - filled segments = the fact (severity-colored), muted segments = the remainder
//  - the in-progress segment fills partially (0.4 months → 40% of a segment)
//  - tick = the target marker
//
//  No text inside — values live in the card's metric row (localization-free,
//  decorative for VoiceOver).
//

import SwiftUI

struct MiniMilestoneGauge: View {
    /// Measured value in milestone units (e.g. 2.4 months).
    let value: Double
    /// Target milestone the tick marks (e.g. 3 months).
    let target: Double
    /// Total segments on the scale (e.g. 6 months).
    let maxValue: Double
    /// Fill tint (severity — the generator knows).
    let color: Color

    var height: CGFloat = 60

    private static let segmentHeight: CGFloat = 10
    private static let segmentGap: CGFloat = 3
    private static let cornerRadius: CGFloat = 3
    private static let tickOvershoot: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let segments = max(1, Int(maxValue.rounded()))
            let gapTotal = Self.segmentGap * CGFloat(segments - 1)
            let segmentWidth = (size.width - gapTotal) / CGFloat(segments)
            let y = (size.height - Self.segmentHeight) / 2
            let clamped = min(max(value, 0), maxValue)

            for i in 0..<segments {
                let x = CGFloat(i) * (segmentWidth + Self.segmentGap)
                let rect = CGRect(x: x, y: y, width: segmentWidth, height: Self.segmentHeight)
                let shape = Path(roundedRect: rect, cornerRadius: Self.cornerRadius)

                // Muted base for every segment.
                context.fill(shape, with: .color(AppColors.textSecondary.opacity(0.18)))

                // Fill: whole segments solid, the in-progress one partially —
                // clip the partial fill to the segment's rounded shape.
                let fillFraction = min(max(clamped - Double(i), 0), 1)
                guard fillFraction > 0 else { continue }
                if fillFraction >= 1 {
                    context.fill(shape, with: .color(color))
                } else {
                    var partial = context
                    partial.clip(to: shape)
                    partial.fill(
                        Path(CGRect(x: x, y: y, width: segmentWidth * CGFloat(fillFraction), height: Self.segmentHeight)),
                        with: .color(color)
                    )
                }
            }

            // Target tick — on the boundary after the `target`-th segment
            // (between segments, like a finish line).
            let targetIndex = min(max(target, 0), maxValue)
            let tickX = CGFloat(targetIndex) * (segmentWidth + Self.segmentGap) - Self.segmentGap / 2
            let tickRect = CGRect(
                x: tickX - 1.25,
                y: y - Self.tickOvershoot,
                width: 2.5,
                height: Self.segmentHeight + Self.tickOvershoot * 2
            )
            context.fill(
                Path(roundedRect: tickRect, cornerRadius: 1.25),
                with: .color(AppColors.textSecondary.opacity(0.7))
            )
        }
        .frame(height: height)
    }
}

// MARK: - Previews

#Preview("Milestone — 2.4 of 6 months, target 3") {
    MiniMilestoneGauge(value: 2.4, target: 3, maxValue: 6, color: AppColors.warning)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Milestone — 0.6 months (critical)") {
    MiniMilestoneGauge(value: 0.6, target: 3, maxValue: 6, color: AppColors.destructive)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Milestone — 5.2 months (healthy)") {
    MiniMilestoneGauge(value: 5.2, target: 3, maxValue: 6, color: AppColors.success)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Milestone — over the scale") {
    MiniMilestoneGauge(value: 9, target: 3, maxValue: 6, color: AppColors.success)
        .frame(width: 120, height: 60)
        .padding()
}
