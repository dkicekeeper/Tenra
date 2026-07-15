//
//  HeroProportionBar.swift
//  Tenra
//
//  Full-size interactive hero sibling of the feed's `MiniProportionBar`
//  (2026-07 visual refresh follow-up). The mini is a text-free stacked bar;
//  at hero size the composition becomes explorable and self-explanatory:
//  - legend rows (color dot + name + share % + amount) make the bar readable
//    without guessing which stripe is which
//  - tapping a segment or its legend row highlights that slice (others dim)
//  - staggered left-to-right entrance, colour-matched glow underlay
//
//  Legend labels/amounts are data-driven (DonutSlice) — no localization keys.
//

import SwiftUI

struct HeroProportionBar: View {
    let segments: [DonutSlice]
    /// ISO currency code for the legend amounts.
    var currency: String = ""
    /// Extra delay before the entrance — pass the nav-transition duration so
    /// the bar animates after the push settles (see InsightDetailView).
    var entranceDelay: Double = 0

    var barHeight: CGFloat = 20
    var segmentGap: CGFloat = 3

    @State private var entered = false
    @State private var selectedID: String?

    private var immediate: Bool { AppAnimation.isReduceMotionEnabled }
    private static let waveStep: Double = 0.08

    private var total: Double { segments.reduce(0.0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            bar
                .chartGlow(radius: 14, yOffset: 8, opacity: 0.5)
            legend
        }
        .onAppear { entered = true }
    }

    // MARK: - Bar

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: segmentGap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    barSegment(segment, index: index, totalWidth: geo.size.width)
                }
            }
            .frame(height: barHeight)
            .clipShape(Capsule())
        }
        .frame(height: barHeight)
        .animation(AppAnimation.chartBannerFade, value: selectedID)
    }

    private func segmentWidth(_ segment: DonutSlice, totalWidth: CGFloat) -> CGFloat {
        let gapTotal: CGFloat = segmentGap * CGFloat(segments.count - 1)
        let fraction: CGFloat = total > 0 ? CGFloat(segment.amount / total) : 0
        // A sliver stays visible as a nub.
        return max(barHeight / 2, (totalWidth - gapTotal) * fraction)
    }

    private func barSegment(_ segment: DonutSlice, index: Int, totalWidth: CGFloat) -> some View {
        let entranceAnimation: Animation? = immediate
            ? nil
            : .spring(response: 0.45, dampingFraction: 0.75)
                .delay(entranceDelay + Double(index) * Self.waveStep)
        return RoundedRectangle(cornerRadius: AppRadius.xl)
            .fill(segment.color)
            .frame(width: segmentWidth(segment, totalWidth: totalWidth))
            .opacity(opacity(for: segment.id))
            .scaleEffect(entered ? 1 : 0.4, anchor: .leading)
            .opacity(entered ? 1 : 0)
            .animation(entranceAnimation, value: entered)
            .onTapGesture { select(segment.id) }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                legendRow(segment)
                    .materialize(
                        delay: entranceDelay + 0.25 + Double(index) * Self.waveStep,
                        animatesOnAppear: !immediate
                    )
            }
        }
        .animation(AppAnimation.chartBannerFade, value: selectedID)
    }

    private func legendRow(_ segment: DonutSlice) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(segment.color)
                .frame(width: 9, height: 9)

            Text(segment.label)
                .font(selectedID == segment.id ? AppTypography.bodyEmphasis : AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AppSpacing.sm)

            Text("\(Int(segment.percentage.rounded()))%")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)

            Text(Formatting.formatCurrencySmart(segment.amount, currency: currency))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)
        }
        .opacity(opacity(for: segment.id))
        .contentShape(Rectangle())
        .onTapGesture { select(segment.id) }
    }

    // MARK: - Selection

    private func opacity(for id: String) -> Double {
        guard let selectedID else { return 1 }
        return selectedID == id ? 1 : 0.35
    }

    private func select(_ id: String) {
        HapticManager.selection()
        selectedID = selectedID == id ? nil : id
    }
}

// MARK: - Previews

#Preview("Hero proportion — subscriptions") {
    HeroProportionBar(
        segments: [
            DonutSlice(id: "1", amount: 9_500, color: .indigo, label: "Netflix", percentage: 48),
            DonutSlice(id: "2", amount: 5_000, color: .teal, label: "Spotify", percentage: 25),
            DonutSlice(id: "3", amount: 3_200, color: .orange, label: "iCloud", percentage: 16),
            DonutSlice(id: "other", amount: 2_100, color: AppColors.textTertiary, label: "Другое", percentage: 11)
        ],
        currency: "KZT"
    )
    .screenPadding()
}

#Preview("Hero proportion — one dominant") {
    HeroProportionBar(
        segments: [
            DonutSlice(id: "1", amount: 20_000, color: .indigo, label: "Аренда", percentage: 91),
            DonutSlice(id: "2", amount: 2_000, color: .teal, label: "Музыка", percentage: 9)
        ],
        currency: "KZT"
    )
    .screenPadding()
}
