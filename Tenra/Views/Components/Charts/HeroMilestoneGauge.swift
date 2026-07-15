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
    /// Extra delay before the entrance wave — pass the nav-transition duration
    /// so the fill animates after the push settles (animating during the zoom
    /// transition made the hero visibly jump at its end).
    var entranceDelay: Double = 0

    @State private var entered = false
    /// One-shot: the entrance delay applies to the first wave only, not tap replays.
    @State private var hasEnteredOnce = false
    /// Suppresses the wave animation while resetting for a replay.
    @State private var suppressAnimation = false
    private var immediate: Bool { !animatesOnAppear || AppAnimation.isReduceMotionEnabled || suppressAnimation }
    private var currentEntranceDelay: Double { hasEnteredOnce ? 0 : entranceDelay }

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
                    AnyShapeStyle(AppColors.textSecondary.opacity(0.18))
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
                        delay: entranceDelay + Double(min(target, clamped)) * Self.waveStep + 0.45,
                        animatesOnAppear: animatesOnAppear
                    )
            }
        }
        .frame(height: segmentHeight + Self.tickOvershoot * 2)
        .contentShape(Rectangle())
        // Tap replays the fill wave (instant reset, then re-enter without the
        // one-shot entrance delay).
        .onTapGesture { replay() }
        .onAppear { entered = true }
    }

    private func replay() {
        guard !AppAnimation.isReduceMotionEnabled, entered else { return }
        HapticManager.light()
        hasEnteredOnce = true
        suppressAnimation = true
        entered = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            suppressAnimation = false
            entered = true
        }
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
                // Glass only on the filled run: glassEffect(.clear) visually
                // swallows the base row's low-alpha gray fill — the muted
                // cells read as fully transparent (2026-07 bug).
                segment(width: segmentWidth * CGFloat(fraction), style: style(i), glass: coveredValue != nil)
                    .opacity(coveredValue == nil || entered ? 1 : 0)
                    .scaleEffect(
                        coveredValue == nil || entered ? 1 : 0.6,
                        anchor: .leading
                    )
                    .animation(
                        coveredValue == nil || immediate
                            ? nil
                            : .spring(response: 0.45, dampingFraction: 0.7)
                                .delay(currentEntranceDelay + Double(i) * Self.waveStep),
                        value: entered
                    )
                    // Keep the HStack slot at full segment width so partial
                    // fills don't shift later segments left.
                    .frame(width: segmentWidth, alignment: .leading)
            }
        }
        .frame(height: segmentHeight + Self.tickOvershoot * 2)
    }

    /// One scale cell. `glass` adds the Liquid Glass sheen — filled run only.
    @ViewBuilder
    private func segment(width: CGFloat, style: AnyShapeStyle, glass: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(style)
            .frame(width: width, height: segmentHeight)
        if glass {
            shape.glassBar(cornerRadius: Self.cornerRadius)
        } else {
            shape
        }
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
