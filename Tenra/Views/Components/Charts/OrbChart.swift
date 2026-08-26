//
//  OrbChart.swift
//  Tenra
//
//  Alternative to `DonutChart` inspired by the Plata "spending sphere": a soft orb whose
//  surface blends every category's colour (angular gradient + heavy blur), ringed by thin
//  perimeter arcs that carry the actual proportions, with percentage labels outside them.
//
//  Takes the same `[DonutSlice]` as `DonutChart` (so callers keep using
//  `DonutSlice.from(items)` and its sliver aggregation). Fully native SwiftUI — no Charts.
//  The specular highlight tracks device motion (CoreMotion) for a live glass-ball feel.
//

import SwiftUI
import CoreMotion

// MARK: - DonutSlice

/// A single slice of a spending breakdown — one category (or a monochromatic subcategory
/// step). Shared input for `OrbChart` (and the compact `MiniDonut`).
struct DonutSlice: Identifiable, Equatable {
    let id: String
    let amount: Double
    let color: Color
    /// Display label (used for VoiceOver / external lists).
    let label: String
    /// 0–100 percentage, used for perimeter labels (shown when large enough).
    let percentage: Double
}

extension DonutSlice {
    /// Slices below this share of the total are visual slivers — they add ring noise
    /// without a readable value, so they're merged into a single "Other" wedge.
    private static let minVisiblePercentage = 5.0
    /// Distinct coloured wedges shown before the rest fold into "Other".
    private static let maxDistinctSlices = 6
    /// A merged "Other" below this share is a hairline, not a wedge — it's dropped entirely
    /// so the ring stays clean. The chart renormalises the remaining wedges to fill 360°,
    /// so one dominant category becomes a solid ring instead of a ring-with-a-sliver.
    private static let negligibleTailPercentage = 3.0

    /// Converts a `CategoryBreakdownItem` array to slices, folding sub-threshold slivers
    /// and any overflow past `maxDistinctSlices` into one "Other" wedge (dropped when that
    /// wedge would itself be a hairline). Assumes `items` is ordered by amount descending
    /// (as the breakdown produces it). The category list below the chart still shows every
    /// exact figure — this only shapes the ring.
    static func from(_ items: [CategoryBreakdownItem]) -> [DonutSlice] {
        var distinct = items.filter { $0.percentage >= minVisiblePercentage }
        // Never collapse to an all-"Other" ring: if everything is a sliver, keep the largest.
        if distinct.isEmpty, let largest = items.max(by: { $0.amount < $1.amount }) {
            distinct = [largest]
        }
        distinct = Array(distinct.prefix(maxDistinctSlices))

        let shownIDs = Set(distinct.map(\.id))
        let merged = items.filter { !shownIDs.contains($0.id) }
        let mergedPercentage = merged.reduce(0) { $0 + $1.percentage }

        var slices = distinct.map {
            DonutSlice(id: $0.id, amount: $0.amount, color: $0.color,
                       label: $0.categoryName, percentage: $0.percentage)
        }
        if !merged.isEmpty, mergedPercentage >= negligibleTailPercentage {
            slices.append(DonutSlice(
                id: "other",
                amount: merged.reduce(0) { $0 + $1.amount },
                color: AppColors.textTertiary,
                label: String(localized: "insights.other"),
                percentage: mergedPercentage
            ))
        }
        return slices
    }

    /// Converts `SubcategoryBreakdownItem` array to opacity-stepped slices of `baseColor`.
    ///
    /// Opacity is distributed linearly between 0.95 (first item) and 0.40 (last item),
    /// regardless of count. This avoids the previous bug where the legacy formula
    /// `index × 0.15 + 0.3` saturated at 1.0 starting from index 5, making all 6th+
    /// subcategories visually identical.
    static func from(_ items: [SubcategoryBreakdownItem], baseColor: Color) -> [DonutSlice] {
        let count = items.count
        let maxOpacity = 0.95
        let minOpacity = 0.40
        return items.enumerated().map { index, item in
            let opacity: Double
            if count <= 1 {
                opacity = maxOpacity
            } else {
                let t = Double(index) / Double(count - 1)
                opacity = maxOpacity - (maxOpacity - minOpacity) * t
            }
            return DonutSlice(
                id: item.id,
                amount: item.amount,
                color: baseColor.opacity(opacity),
                label: item.name,
                percentage: item.percentage
            )
        }
    }
}

struct OrbChart: View {
    let slices: [DonutSlice]
    /// Ring height (square). Matches `DonutChart`'s full mode by default.
    var size: CGFloat = 280
    /// What the perimeter labels show: slice percentages (default) or slice
    /// names (wealth composition — account names beat raw percentages there).
    enum LabelStyle {
        case percent
        case name
    }

    /// Percentage labels around the perimeter. Off for monochrome breakdowns where the
    /// numbers would clutter (mirrors `DonutChart`'s `showAnnotations`).
    var showLabels: Bool = true
    /// Perimeter label content — percent (default) or slice names.
    var labelStyle: LabelStyle = .percent
    /// Plays the staged entrance on first appear; set `false` for re-mounts
    /// (e.g. `.id(index)` pager pages) so it doesn't replay.
    var animatesOnAppear: Bool = true
    /// Category icon rendered white in the sphere centre (shown when non-nil and `showsCenterIcon`).
    var centerIcon: IconSource? = nil
    /// Toggle for the centre icon, independent of whether one is provided.
    var showsCenterIcon: Bool = true

    /// Single entrance driver — flipped once; each layer keys its own delayed animation
    /// off it, so the orb, then the arcs, then the labels come in in sequence.
    @State private var entered = false
    @State private var motion = OrbMotionModel()

    /// Show everything at once with no motion (re-mounts, Reduce Motion).
    private var immediate: Bool { !animatesOnAppear || AppAnimation.isReduceMotionEnabled }

    /// Cumulative normalized boundaries [0…1] (clockwise from the top), one more entry
    /// than `slices`. Slice `i` spans `[boundaries[i], boundaries[i+1]]`.
    private var boundaries: [CGFloat] {
        let total = slices.reduce(0.0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        var acc: CGFloat = 0
        var result: [CGFloat] = [0]
        result.reserveCapacity(slices.count + 1)
        for slice in slices { acc += CGFloat(slice.amount / total); result.append(acc) }
        return result
    }

    /// Largest slice — its colour anchors fallbacks.
    private var dominantColor: Color {
        slices.max(by: { $0.amount < $1.amount })?.color ?? AppColors.accent
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let bounds = boundaries

            ZStack {
                orb(side: side)
                perimeterArcs(side: side, center: center, bounds: bounds)
                if showLabels {
                    labels(side: side, center: center, bounds: bounds)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: size)
        .onAppear {
            entered = true
            if !AppAnimation.isReduceMotionEnabled { motion.start() }
        }
        .onDisappear { motion.stop() }
    }

    // MARK: - Orb

    /// The blended sphere: colour core + motion-tracked specular highlight + glass surface,
    /// grounded by a blurred angular-gradient shadow. Enters with a spring "pop" that also
    /// sharpens out of a blur (materialise).
    private func orb(side: CGFloat) -> some View {
        let diameter = side * 0.52
        let radius = diameter / 2
        return colorCore(diameter: diameter, radius: radius)
            .overlay { SpecularHighlight(radius: radius, motion: motion) }
            .glassSphere()
//            .overlay {
//                // Rim: bright at the top, fading down — reads as a glass edge catching light.
//                Circle().strokeBorder(
//                    LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08)],
//                                   startPoint: .top, endPoint: .bottom),
//                    lineWidth: 1)
//            }
            .overlay { centerIconView }
            .background { orbShadow(diameter: diameter, radius: radius) }
            .scaleEffect(entered ? 1 : 0.5)
            .opacity(entered ? 1 : 0)
            .blur(radius: entered ? 0 : radius * 0.25)
            .animation(immediate ? nil : .spring(response: 0.55, dampingFraction: 0.6),
                       value: entered)
    }

    /// White category icon on the sphere. `.circle` with a nil background = glyph only.
    @ViewBuilder
    private var centerIconView: some View {
        if showsCenterIcon, let centerIcon {
            IconView(
                source: centerIcon,
                style: .circle(size: AppIconSize.ultra, tint: .monochrome(.white), backgroundColor: nil)
            )
        }
    }

    /// The saturated colour surface: each slice's colour in its angular band, blurred to blend.
    private func colorCore(diameter: CGFloat, radius: CGFloat) -> some View {
        AngularGradient(
            gradient: Gradient(stops: orbStops),
            center: .center,
            startAngle: .degrees(-90),   // start at the top, matching the arcs
            endAngle: .degrees(270)
        )
        // Oversize then clip so the blurred edge stays fully opaque to the rim.
        .frame(width: diameter * 1.3, height: diameter * 1.3)
        .blur(radius: radius * 0.5)
        .frame(width: diameter, height: diameter)
        .saturation(2) // keep the category colours vivid through the blur
        .clipShape(Circle())
    }

    /// Colour-matched shadow: the same angular blend, blurred and dropped below the orb, so
    /// the cast picks up every category's colour instead of a single flat tint.
    private func orbShadow(diameter: CGFloat, radius: CGFloat) -> some View {
        AngularGradient(
            gradient: Gradient(stops: orbStops),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .blur(radius: radius * 0.5)
        .saturation(2)
        .scaleEffect(1.08)
        .offset(y: radius * 0.22)
        .opacity(0.6)
    }

    /// Angular-gradient stops: each slice is a solid colour band from its start to its end
    /// boundary; the blur softens the hard boundaries into a blend.
    private var orbStops: [Gradient.Stop] {
        let bounds = boundaries
        guard bounds.count == slices.count + 1 else {
            return [Gradient.Stop(color: dominantColor, location: 0),
                    Gradient.Stop(color: dominantColor, location: 1)]
        }
        var stops: [Gradient.Stop] = []
        for index in slices.indices {
            stops.append(.init(color: slices[index].color, location: bounds[index]))
            stops.append(.init(color: slices[index].color, location: bounds[index + 1]))
        }
        return stops
    }

    // MARK: - Perimeter arcs

    private func perimeterArcs(side: CGFloat, center: CGPoint, bounds: [CGFloat]) -> some View {
        let arcDiameter = side * 0.66
        let arcWidth = side * 0.016 // thin line around the orb
        let gap: CGFloat = 0.008 // angular gap between arcs (fraction of the circle)
        return ForEach(slices.indices, id: \.self) { index in
            if index + 1 < bounds.count {
                let start = bounds[index]
                let end = bounds[index + 1]
                // Skip wedges too thin to render as a rounded arc.
                if end - start > gap * 2.2 {
                    Circle()
                        .trim(from: start + gap, to: entered ? end - gap : start + gap)
                        .stroke(slices[index].color,
                                style: StrokeStyle(lineWidth: arcWidth, lineCap: .round))
                        .frame(width: arcDiameter, height: arcDiameter)
                        .rotationEffect(.degrees(-90))
                        .position(center)
                        // Draw in after the orb, each arc a beat behind the last (clockwise sweep).
                        .animation(immediate ? nil
                                   : .easeOut(duration: 0.5).delay(0.3 + Double(index) * 0.07),
                                   value: entered)
                }
            }
        }
    }

    // MARK: - Labels

    private func labels(side: CGFloat, center: CGPoint, bounds: [CGFloat]) -> some View {
        // Sits well outside the arcs (centreline 0.33·side) so labels never touch the lines.
        let labelRadius = side * 0.44
        return ForEach(slices.indices, id: \.self) { index in
            if index + 1 < bounds.count, slices[index].percentage >= 2 {
                let midFraction = (bounds[index] + bounds[index + 1]) / 2
                let angle = midFraction * 2 * .pi
                labelText(for: index)
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .opacity(entered ? 1 : 0)
                    .position(
                        x: center.x + labelRadius * sin(angle),
                        y: center.y - labelRadius * cos(angle)
                    )
                    .animation(immediate ? nil
                               : .easeInOut(duration: 0.6).delay(0.85 + Double(index) * 0.05),
                               value: entered)
            }
        }
    }
}

// MARK: - Label content

private extension OrbChart {
    /// Perimeter label content for slice `index`, by `labelStyle`.
    @ViewBuilder
    func labelText(for index: Int) -> some View {
        switch labelStyle {
        case .percent:
            // Roll the number up from 0 with .numericText once the arcs are in.
            let value = entered ? slices[index].percentage : 0
            Text(String(format: "%.0f%%", value))
                .contentTransition(.numericText())
        case .name:
            Text(slices[index].label)
                .lineLimit(1)
                .frame(maxWidth: 96)
        }
    }
}

// MARK: - Specular highlight (motion-tracked)

/// The moving gloss spot. Isolated into its own view so the ~30 Hz motion updates only
/// invalidate this small layer, not the whole orb (which carries the expensive glass/blur).
private struct SpecularHighlight: View {
    let radius: CGFloat
    var motion: OrbMotionModel

    var body: some View {
        let amplitude: CGFloat = 1.0 // how far the highlight travels across the surface
        let base = UnitPoint(x: 0.3, y: 0.2)
        RadialGradient(
            colors: [.white.opacity(0.8), .white.opacity(0)],
            center: UnitPoint(x: base.x + motion.offset.width * amplitude,
                              y: base.y + motion.offset.height * amplitude),
            startRadius: 1,
            endRadius: radius * 1.2
        )
        .blur(radius: radius * 0.18)
        // `.screen` lightens smoothly; `.colorDodge` blew bright colours (yellow) past a
        // threshold and left a hard-edged disc when the highlight sat over them.
        .blendMode(.screen)
        .clipShape(Circle())
    }
}

// MARK: - Motion model

/// Publishes a normalised (−1…1) tilt offset from device gravity, smoothed. Drives the
/// specular highlight so the orb's shine shifts as the phone tilts. No-ops where device
/// motion is unavailable (Simulator), leaving the highlight at rest.
@MainActor
@Observable
final class OrbMotionModel {
    /// Smoothed tilt relative to the neutral pose, each axis roughly −1…1.
    var offset: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    /// Gravity captured on the first reading — the pose the phone is in when the orb appears
    /// (held in front of the face). Offsets are measured from here, so the highlight rests at
    /// its base (top-left) in that pose instead of flying off when gravity ≠ 0.
    @ObservationIgnored private var reference: (x: Double, y: Double)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        reference = nil
        offset = .zero
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            if self.reference == nil { self.reference = (gravity.x, gravity.y) }
            let ref = self.reference ?? (gravity.x, gravity.y)
            // Low-pass filter so the highlight glides instead of jittering.
            let smoothing: CGFloat = 0.12
            // Inverted axes so the glint moves to the opposite corner from the tilt; measured
            // from the neutral pose so "in front of the face" keeps it at the top-left.
            let targetX = CGFloat(-(gravity.x - ref.x))
            let targetY = CGFloat(gravity.y - ref.y)
            self.offset.width += (targetX - self.offset.width) * smoothing
            self.offset.height += (targetY - self.offset.height) * smoothing
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
    }
}

// MARK: - Glass surface

private extension View {
    /// Liquid Glass sphere surface. `.clear` keeps content visible and saturated
    /// — it adds the reflective glass sheen without the frosted blur `.regular` would apply.
    func glassSphere() -> some View {
        glassEffect(.clear, in: .circle)
    }
}

// MARK: - Previews

#Preview("Orb — category breakdown") {
    OrbChart(slices: DonutSlice.from(CategoryBreakdownItem.mockItems()))
        .screenPadding()
        .padding(.vertical, AppSpacing.xl)
}

#Preview("Orb — dominant category") {
    let items = [
        CategoryBreakdownItem(id: "transport", categoryName: "Transport", amount: 236,
                              percentage: 99.2, color: AppColors.accent, iconSource: nil, subcategories: []),
        CategoryBreakdownItem(id: "clothing", categoryName: "Clothing", amount: 2,
                              percentage: 0.8, color: .pink, iconSource: nil, subcategories: [])
    ]
    return OrbChart(slices: DonutSlice.from(items))
        .screenPadding()
        .padding(.vertical, AppSpacing.xl)
}
